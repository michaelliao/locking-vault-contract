// SPDX-License-Identifier: GPLv3

pragma solidity =0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract LockingVault {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    event Locked(
        uint256 indexed id,
        address indexed owner,
        address indexed token,
        uint256 total,
        uint64 startAt,
        uint64 endAt
    );

    event Withdrawed(
        uint256 indexed id,
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 balance
    );

    struct Lock {
        address token; // token address (immutable)
        uint256 total; // total locked (immutable)
        uint256 balance; // current amount balance (mutable)
        uint64 startAt; // locked start time (immutable)
        uint64 lastAt; // last time to withdraw (mutable)
        uint64 endAt; // end time to unlock all (immutable)
    }

    mapping(address => EnumerableSet.UintSet) private addressMap;

    mapping(uint256 => Lock) private lockMap;

    uint256 nextId;

    function lockInfo(uint256 id) public view returns (Lock memory) {
        return lockMap[id];
    }

    function lockIds(address owner) public view returns (uint256[] memory) {
        return addressMap[owner].values();
    }

    function lockToken(
        address token,
        uint64 startAt,
        uint64 endAt,
        address[] memory owners,
        uint256[] memory amounts
    ) external {
        require(token != address(0), "zero address");
        uint256 len = owners.length;
        require(len > 0, "zero array");
        require(len == amounts.length, "invalid amounts");
        require(endAt > startAt, "invalid end time");

        uint256 total = 0;
        uint256 i;
        for (i = 0; i < len; i++) {
            address owner = owners[i];
            require(owner != address(0), "zero address");
            uint256 amount = amounts[i];
            require(amount > 0, "zero amount");
            // set lock:
            nextId++;
            lockMap[nextId] = Lock(
                token,
                amount, // total = amount
                amount, // balance = amount
                startAt,
                startAt, // lastAt = startAt
                endAt
            );
            addressMap[owner].add(nextId);
            emit Locked(nextId, owner, token, amount, startAt, endAt);
            total += amount;
        }
        // transfer token into contract:
        (IERC20(token)).safeTransferFrom(msg.sender, address(this), total);
    }

    /**
     * Withdraw unlocked token by id list.
     *
     * Note that the id list must NOT duplicate. ALL locks of ids must be in release state.
     */
    function withdrawToken(uint256[] memory ids) external {
        uint256 idLength = ids.length;
        uint256 i;
        uint64 ts = uint64(block.timestamp);
        for (i = 0; i < idLength; i++) {
            uint256 id = ids[i];
            EnumerableSet.UintSet storage set = addressMap[msg.sender];
            require(set.contains(id), "id not exist");
            Lock storage lock = lockMap[id];
            require(ts > lock.lastAt, "still locked");
            // calculate how many token is unlocked:
            uint256 canWithdraw = (lock.endAt <= ts)
                ? lock.balance
                : (lock.balance * (ts - lock.lastAt)) /
                    (lock.endAt - lock.lastAt);
            (IERC20(lock.token)).safeTransfer(msg.sender, canWithdraw);
            uint256 left = lock.balance - canWithdraw;
            if (left > 0) {
                lock.balance = left;
                lock.lastAt = ts;
            } else {
                // remove lock:
                delete lockMap[id];
                set.remove(id);
            }
            emit Withdrawed(id, msg.sender, lock.token, canWithdraw, left);
        }
    }
}
