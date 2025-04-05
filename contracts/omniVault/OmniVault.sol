// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OmniVaultProtocols.sol";
import "../interfaces/IMessageTransmitter.sol";

contract OmniVault is OmniVaultProtocols {

    event HyperlaneLog(bool success, bytes data);
    event CCTPLog(bool success, bytes data);
    event TotalSupplyUpdated(uint32 chainId, uint256 totalSupply, uint256 reqId);
    event CCTPRelaying(bytes32 messageId, uint32 srcChainId, uint32 dstChainId, bytes body);
    event MessageCommitted(ProtocolType protocolType, bytes32 messageId);
    event MessageExecuted(bytes32 messageId);

    struct Path {
        uint32 actionChainId; // Defi Action ChainId
        ProtocolType protocolId;
        uint256 amount;
        address recipient;
    }

    modifier onlyMailBox() {
        require(msg.sender == _getProtocolStorage().protocols[ProtocolType.HYPERLANE], "Only MailBox can call this function");
        _;
    }

    function setOsyUSD(address _osyUSDC) external onlyOwner {
        _setOSYUSDC(_osyUSDC);
    }

    function setLsdCore(address _lsdCore) external onlyOwner {
        _setLsdCore(_lsdCore);
    }

    function setProtocol(ProtocolType _protocolType, address _protocol) external onlyOwner {
        _setProtocol(_protocolType, _protocol);
    }

    function setUSDC(address _USDC) external onlyOwner {
        _setUSDC(_USDC);
    }

    function handleCCTP(bytes memory _message, bytes memory _attestation, bytes32 _messageId, bytes memory _body) external onlyOwner {
        IMessageTransmitter(_getProtocolStorage().protocols[ProtocolType.CCTP_TRANSMIITER]).receiveMessage(_message, _attestation);

        _getProtocolStorage().cctpMessageIds[_messageId] = true;
        emit MessageCommitted(ProtocolType.CCTP, _messageId);

        if (_getProtocolStorage().hyperlaneMessageIds[_messageId]) {
            try this.executeHandleCCTP(_body) {
                emit CCTPLog(true, _body);
            } catch {
                emit CCTPLog(false, _body);
            }
        }
    }

    function executeHandleCCTP(bytes memory _body) external {
        require(msg.sender == address(this), "Only Vault can call this function");
        (bool success,) = address(this).call(_body);
        require(success, "Handle call failed");
    }

    function handle(uint32, bytes32 _sender, bytes calldata _body) external onlyMailBox() {
        require(_sender == bytes32(uint256(uint160(address(this)))), "Invalid sender");
        try this.executeHandle(_body) {
            emit HyperlaneLog(true, _body);
        } catch {
            emit HyperlaneLog(false, _body);
        }
    }

    function executeHandle(bytes calldata _body) external {
        require(msg.sender == address(this), "Only Vault can call this function");
        (bool success,) = address(this).call(_body);
        require(success, "Handle call failed");
    }

    // manager (owner)
    // Path example: [ (11155111, ProtocolType.AAVE, 1 * 10**6, address(0)), (84532, ProtocolType.COMPOUND, 1 * 10**6, address(0)) ]
    function withdrawAndBridgeAndDeposit(Path[] memory actions) external onlyOwner {
        require(actions.length == 2, "Invalid action length");
        require(actions[0].actionChainId == block.chainid, "Invalid action chainId");

        Path[] memory remainActions = new Path[](1);
        remainActions[0] = actions[1];

        // Currently using simple nonce, but will enhance security by generating more complex message ID in the future
        bytes32 messageId = keccak256(abi.encodePacked(
            _getProtocolStorage().nonce[actions[1].actionChainId]
        ));

        _getProtocolStorage().nonce[actions[1].actionChainId]++;

        _withdraw(actions[0].protocolId, actions[0].amount);

        bytes memory body = abi.encodeWithSignature("crossChainDeposit((uint32,uint8,uint256,address)[],bytes32)", remainActions, messageId);
        
        _messageToHyperlane(actions[1].actionChainId, body);
        _bridgeToCCTP(actions[1].actionChainId, actions[0].amount);

        emit CCTPRelaying(messageId, actions[0].actionChainId, actions[1].actionChainId, body);
    }

    // user
    // Path example: [ (11155111, ProtocolType.AAVE, 1 * 10**6, address(user)) ]
    function deposit(Path[] memory actions) external {
        require(actions.length == 1, "Invalid action length");
        require(actions[0].actionChainId == 11155111 || actions[0].actionChainId == 84532, "Invalid action chainId");

        IERC20(_getProtocolStorage().USDC).transferFrom(msg.sender, address(this), actions[0].amount);

        if (actions[0].actionChainId == block.chainid) {
            _deposit(actions[0].protocolId, actions[0].amount);
            if (block.chainid == 11155111) {
                _getProtocolStorage().lsdCore.mint(msg.sender, actions[0].amount);
            } else {
                _messageToHyperlane(11155111, abi.encodeWithSignature("crossChainMinting((uint32,uint8,uint256,address)[])", actions));
            }
        } else {
            if (block.chainid == 11155111) {
                _getProtocolStorage().lsdCore.mint(msg.sender, actions[0].amount);
            }

            bytes32 messageId = keccak256(abi.encodePacked(
                _getProtocolStorage().nonce[actions[0].actionChainId]
            ));

            _getProtocolStorage().nonce[actions[0].actionChainId]++;
            _bridgeToCCTP(actions[0].actionChainId, actions[0].amount);
            emit CCTPRelaying(messageId, uint32(block.chainid), actions[0].actionChainId, abi.encodeWithSignature("crossChainDeposit((uint32,uint8,uint256,address)[],bytes32)", actions, messageId));

            _messageToHyperlane(actions[0].actionChainId, abi.encodeWithSignature("crossChainDeposit((uint32,uint8,uint256,address)[],bytes32)", actions, messageId));
        }
    }

    // user
    // Path example: [ (11155111, ProtocolType.AAVE, 1 * 10**6, address(user)) ]
    function withdraw(Path[] memory actions) external {
        require(actions.length == 1, "Invalid action length");
        require(block.chainid == 11155111, "Invalid action chainId"); // Withdraw is only possible on Sepolia
        require(actions[0].actionChainId == 11155111 || actions[0].actionChainId == 84532, "Invalid action chainId");

        IERC20(_getProtocolStorage().osyUSDC).transferFrom(msg.sender, address(this), actions[0].amount);
        _getProtocolStorage().lsdCore.burn(actions[0].amount);

        if (actions[0].actionChainId == block.chainid) {
            _withdraw(actions[0].protocolId, actions[0].amount);
            IERC20(_getProtocolStorage().USDC).transfer(actions[0].recipient, actions[0].amount);
        } else {
            _withdraw(actions[0].protocolId, actions[0].amount);

            bytes32 messageId = keccak256(abi.encodePacked(
                _getProtocolStorage().nonce[actions[0].actionChainId]
            ));

            _getProtocolStorage().nonce[actions[0].actionChainId]++;
            _bridgeToCCTP(actions[0].actionChainId, actions[0].amount);
            emit CCTPRelaying(messageId, uint32(block.chainid), actions[0].actionChainId, abi.encodeWithSignature("crossChainWithdraw((uint32,uint8,uint256,address)[],bytes32)", actions, messageId));
                
            _messageToHyperlane(actions[0].actionChainId, abi.encodeWithSignature("crossChainWithdraw((uint32,uint8,uint256,address)[],bytes32)", actions, messageId));
        }
    }

    // bridge call
    function crossChainDeposit(Path[] memory actions, bytes32 _messageId) external {
        require(msg.sender == address(this), "Only Vault can call this function");
        require(actions.length == 1, "Invalid action length");
        require(actions[0].actionChainId == block.chainid, "Invalid action chainId");

        if (_getProtocolStorage().cctpMessageIds[_messageId]) {
            _getProtocolStorage().hyperlaneMessageIds[_messageId] = true;
            _deposit(actions[0].protocolId, actions[0].amount);
            if (block.chainid == 11155111 && actions[0].recipient != address(0)) {
                _getProtocolStorage().lsdCore.mint(actions[0].recipient, actions[0].amount);
            }
            emit MessageExecuted(_messageId);
        } else {
            _getProtocolStorage().hyperlaneMessageIds[_messageId] = true;
            emit MessageCommitted(ProtocolType.HYPERLANE, _messageId);
        }
    }

    // bridge call
    function crossChainWithdraw(Path[] memory actions, bytes32 _messageId) external {
        require(msg.sender == address(this), "Only Vault can call this function");
        require(actions.length == 1, "Invalid action length");
        require(actions[0].actionChainId == block.chainid, "Invalid action chainId");

        if (_getProtocolStorage().cctpMessageIds[_messageId]) {
            _getProtocolStorage().hyperlaneMessageIds[_messageId] = true;
            IERC20(_getProtocolStorage().USDC).transfer(actions[0].recipient, actions[0].amount);
            emit MessageExecuted(_messageId);
        } else {
            _getProtocolStorage().hyperlaneMessageIds[_messageId] = true;
            emit MessageCommitted(ProtocolType.HYPERLANE, _messageId);
        }
    }

    function crossChainMinting(Path[] memory actions) external {
        require(msg.sender == address(this), "Only Vault can call this function");
        require(actions.length == 1, "Invalid action length");
        require(actions[0].actionChainId == block.chainid, "Invalid action chainId");
        require(actions[0].recipient != address(0), "Invalid recipient");
        require(block.chainid == 11155111, "Invalid action chainId");
        _getProtocolStorage().lsdCore.mint(actions[0].recipient, actions[0].amount);
    }

    function requestTotalSupply(uint256 _reqId) external payable onlyOwner {
        require(block.chainid == 84532, "Invalid action chainId");
        _messageToHyperlane(11155111, abi.encodeWithSignature("updateTotalSupply(uint32,uint256,uint256)", block.chainid, _totalSupply(), _reqId));
    }

    // Main chain only function
    function updateTotalSupply(uint32 _chainId, uint256 _newTotalSupply, uint256 _reqId) external {
        require(msg.sender == address(this), "Only Vault can call this function or owner");
        require(block.chainid == 11155111, "Invalid action chainId");
        _updateTotalSupply(_chainId, _newTotalSupply);
        emit TotalSupplyUpdated(_chainId, _newTotalSupply, _reqId);

    }

    function applyInterest() external {
        require(block.chainid == 11155111, "Invalid action chainId");
        _updateTotalSupply(11155111, _totalSupply());
        uint256 totalAmount = _protocolTotalSupply();
        _getProtocolStorage().lsdCore.applyInterest(totalAmount);
    }

    // Query how much the vault holds on the target chain
    function totalSupply(uint32 _chainId) external view returns (uint256) {
        return _getProtocolStorage().totalSupplyOfVaults[_chainId];
    }

    // Functions used on each chain
    function currentChainSupply() external view returns (uint256) {
        return _totalSupply();
    }

    function ownerCall(address _target, bytes memory _data) external onlyOwner {
        (bool success,) = _target.call(_data);
        require(success, "Owner call failed");
    }
}
