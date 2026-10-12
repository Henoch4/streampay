// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StreamPay — per-second native BOT payment streams.
/// Sender opens a stream with deposited BOT; recipient withdraws whatever has
/// vested at any time; sender can cancel, which settles vested-to-recipient
/// and refunds the rest. Payroll, grants, subscriptions.
contract StreamPay is ReentrancyGuard {
    struct Stream {
        address sender;
        address recipient;
        uint256 deposit;
        uint256 withdrawn;
        uint64 start;
        uint64 duration;
        bool cancelled;
    }

    Stream[] private _streams;

    event StreamCreated(uint256 indexed id, address indexed sender, address indexed recipient, uint256 deposit, uint64 duration);
    event Withdrawn(uint256 indexed id, address indexed recipient, uint256 amount);
    event StreamCancelled(uint256 indexed id, uint256 toRecipient, uint256 toSender);

    function create(address recipient, uint64 durationSecs) external payable nonReentrant returns (uint256) {
        require(recipient != address(0), "Zero recipient");
        require(msg.value > 0, "Bad deposit");
        require(durationSecs > 0, "Bad duration");
        _streams.push(Stream({
            sender: msg.sender,
            recipient: recipient,
            deposit: msg.value,
            withdrawn: 0,
            start: uint64(block.timestamp),
            duration: durationSecs,
            cancelled: false
        }));
        uint256 id = _streams.length - 1;
        emit StreamCreated(id, msg.sender, recipient, msg.value, durationSecs);
        return id;
    }

    function flowed(uint256 id) public view returns (uint256) {
        Stream storage s = _streams[id];
        uint256 t = block.timestamp;
        if (t <= s.start) return 0;
        uint256 end = uint256(s.start) + s.duration;
        if (t >= end) return s.deposit;
        return (s.deposit * (t - s.start)) / s.duration;
    }

    function withdraw(uint256 id) external nonReentrant {
        Stream storage s = _streams[id];
        require(msg.sender == s.recipient, "Not recipient");
        require(!s.cancelled, "Cancelled");
        uint256 pay = flowed(id) - s.withdrawn;
        require(pay > 0, "Nothing vested");
        s.withdrawn += pay;
        (bool ok, ) = s.recipient.call{value: pay}("");
        require(ok, "Pay failed");
        emit Withdrawn(id, s.recipient, pay);
    }

    function cancel(uint256 id) external nonReentrant {
        Stream storage s = _streams[id];
        require(msg.sender == s.sender, "Not sender");
        require(!s.cancelled, "Cancelled");
        s.cancelled = true;
        uint256 f = flowed(id);
        uint256 toRec = f - s.withdrawn;
        uint256 toSend = s.deposit - f;
        s.withdrawn = f;
        if (toRec > 0) {
            (bool ok1, ) = s.recipient.call{value: toRec}("");
            require(ok1, "Rec pay failed");
        }
        if (toSend > 0) {
            (bool ok2, ) = s.sender.call{value: toSend}("");
            require(ok2, "Sender pay failed");
        }
        emit StreamCancelled(id, toRec, toSend);
    }

    function totalStreams() external view returns (uint256) {
        return _streams.length;
    }

    function getStream(uint256 id)
        external
        view
        returns (address sender, address recipient, uint256 deposit, uint256 withdrawn, uint64 start, uint64 duration, bool cancelled)
    {
        Stream storage s = _streams[id];
        return (s.sender, s.recipient, s.deposit, s.withdrawn, s.start, s.duration, s.cancelled);
    }
}
