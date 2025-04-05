// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC20.sol";
import "../interfaces/IPool.sol";
import "../interfaces/CometMainInterface.sol";
import "../interfaces/ITokenMessenger.sol";
import "../interfaces/IMailBox.sol";
import "../interfaces/ILsdCore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract OmniVaultProtocols is Initializable, Ownable {

    // storage slot
    bytes32 private constant PROTOCOL_STORAGE_SLOT = keccak256(abi.encodePacked("PROTOCOLS.STORAGE"));

    // protocol type (extensible)
    enum ProtocolType {
        AAVE,
        COMPOUND,
        CCTP,
        CCTP_TRANSMIITER,
        HYPERLANE,
        HYPERLANE_GAS_PAYMASTER
    }

    struct ProtocolStorage {
        IERC20 osyUSDC;
        IERC20 USDC;
        IERC20 AaveUSDC;
        ILsdCore lsdCore;
        mapping(ProtocolType protocolType => address protocolAddr) protocols;
        mapping(address protocolAddr => address tokenAddr) bearingTokens;
        mapping(uint32 chainId => uint256 totalSupply) totalSupplyOfVaults;
        mapping(bytes32 messageId => bool committed) hyperlaneMessageIds;
        mapping(bytes32 messageId => bool committed) cctpMessageIds;
        mapping(uint32 chainId => uint256 nonce) nonce;
    }

    modifier onlyProtocol(ProtocolType _protocolType) {
        if (_getProtocolStorage().protocols[_protocolType] == address(0)) {
            revert("Protocol not set");
        }
        _;
    }

    receive() external payable {}

    // Set testnet addresses according to chain ID (can be extended later, currently using constants)
    constructor() Ownable(msg.sender) {
        initialize();
    }

    function initialize() public initializer {
        _transferOwnership(msg.sender);

        if (block.chainid == 11155111) { // sepolia

            _setUSDC(address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238));
            _setProtocol(ProtocolType.AAVE, address(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951));
            _setProtocol(ProtocolType.CCTP, address(0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5));
            _setProtocol(ProtocolType.CCTP_TRANSMIITER, address(0x7865fAfC2db2093669d92c0F33AeEF291086BEFD));
            _setProtocol(ProtocolType.HYPERLANE, address(0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766));
            _setProtocol(ProtocolType.HYPERLANE_GAS_PAYMASTER, address(0x6f2756380FD49228ae25Aa7F2817993cB74Ecc56));

            _setAaveUSDC(address(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8)); // Aave doesn't use Circle's USDC (in testnet)
            _getProtocolStorage().AaveUSDC.approve(address(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951), type(uint256).max); // Pre-approve separately

            _setBearingToken(ProtocolType.AAVE, address(0x16dA4541aD1807f4443d92D26044C1147406EB80));

        } else if (block.chainid == 84532) { // base sepolia

            _setUSDC(address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
            _setProtocol(ProtocolType.COMPOUND, address(0x571621Ce60Cebb0c1D442B5afb38B1663C6Bf017));
            _setProtocol(ProtocolType.CCTP, address(0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5));
            _setProtocol(ProtocolType.CCTP_TRANSMIITER, address(0x7865fAfC2db2093669d92c0F33AeEF291086BEFD));
            _setProtocol(ProtocolType.HYPERLANE, address(0x6966b0E55883d49BFB24539356a2f8A673E02039));
            _setProtocol(ProtocolType.HYPERLANE_GAS_PAYMASTER, address(0x28B02B97a850872C4D33C3E024fab6499ad96564));

            _setBearingToken(ProtocolType.COMPOUND, address(0x571621Ce60Cebb0c1D442B5afb38B1663C6Bf017));

        } else {
            revert("Unsupported chain");
        }
    }

    function _deposit(ProtocolType _protocolType, uint256 _amount) internal onlyProtocol(_protocolType) {
        if (_protocolType == ProtocolType.AAVE) {
            _depositToAave(_amount);
        } else if (_protocolType == ProtocolType.COMPOUND) {
            _depositToCompound(_amount);
        }
    }

    function _depositToAave(uint256 _amount) internal {
        IPool(_getProtocolStorage().protocols[ProtocolType.AAVE]).supply(address(_getProtocolStorage().AaveUSDC), _amount, address(this), 0);
    }

    function _depositToCompound(uint256 _amount) internal {
        CometMainInterface(_getProtocolStorage().protocols[ProtocolType.COMPOUND]).supply(address(_getProtocolStorage().USDC), _amount);
    }

    function _withdraw(ProtocolType _protocolType, uint256 _amount) internal onlyProtocol(_protocolType) {
        if (_protocolType == ProtocolType.AAVE) {
            _withdrawFromAave(_amount);
        } else if (_protocolType == ProtocolType.COMPOUND) {
            _withdrawFromCompound(_amount);
        }
    }

    function _withdrawFromAave(uint256 _amount) internal {
        IPool(_getProtocolStorage().protocols[ProtocolType.AAVE]).withdraw(address(_getProtocolStorage().AaveUSDC), _amount, address(this));
    }

    function _withdrawFromCompound(uint256 _amount) internal {
        CometMainInterface(_getProtocolStorage().protocols[ProtocolType.COMPOUND]).withdraw(address(_getProtocolStorage().USDC), _amount);
    }

    function _bridgeToCCTP(uint32 _toChainId, uint256 _amount) internal {
        uint32 destinationDomain;

        if (_toChainId == 11155111) { // sepolia
            destinationDomain = 0;
        } else if (_toChainId == 84532) { // base sepolia
            destinationDomain = 6;
        } else {
            revert("Unsupported chain");
        }

        ITokenMessenger(_getProtocolStorage().protocols[ProtocolType.CCTP]).depositForBurn(_amount, destinationDomain, bytes32(uint256(uint160(address(this)))), address(_getProtocolStorage().USDC));
    }

    function _messageToHyperlane(uint32 _toChainId, bytes memory _body) internal {

        require(_toChainId == 11155111 || _toChainId == 84532, "Unsupported chain");

        uint256 fee = IMailBox(_getProtocolStorage().protocols[ProtocolType.HYPERLANE]).quoteDispatch(_toChainId, bytes32(uint256(uint160(address(this)))), _body);

        bytes32 messageId = IMailBox(_getProtocolStorage().protocols[ProtocolType.HYPERLANE]).dispatch{value: fee}(_toChainId, bytes32(uint256(uint160(address(this)))), _body);
        IMailBox(_getProtocolStorage().protocols[ProtocolType.HYPERLANE_GAS_PAYMASTER]).payForGas{value: address(this).balance}(messageId, _toChainId, 2000000, address(this));
    }

    function _setUSDC(address _USDC) internal {
        _getProtocolStorage().USDC = IERC20(_USDC);
    }

    function _setLsdCore(address _lsdCore) internal {
        _getProtocolStorage().lsdCore = ILsdCore(_lsdCore);
    }

    function _setOSYUSDC(address _OSYUSDC) internal {
        _getProtocolStorage().osyUSDC = IERC20(_OSYUSDC);
    }

    function _setAaveUSDC(address _AaveUSDC) internal {
        _getProtocolStorage().AaveUSDC = IERC20(_AaveUSDC);
    }

    function _setProtocol(ProtocolType protocolType, address protocolAddr) internal {
        _getProtocolStorage().protocols[protocolType] = protocolAddr;
        _getProtocolStorage().USDC.approve(protocolAddr, type(uint256).max);
    }

    function _setBearingToken(ProtocolType protocolType, address tokenAddr) internal {
        _getProtocolStorage().bearingTokens[_getProtocolStorage().protocols[protocolType]] = tokenAddr;
    }

    function _updateTotalSupply(uint32 _chainId, uint256 _newTotalSupply) internal {
        if (_chainId == 11155111) {
            _getProtocolStorage().totalSupplyOfVaults[_chainId] = _totalSupply();
        } else if (_chainId == 84532) {
            _getProtocolStorage().totalSupplyOfVaults[_chainId] = _newTotalSupply;
        } else {
            revert("Unsupported chain");
        }
    }

    function _totalSupply() internal view returns (uint256) {
        if (block.chainid == 11155111) {
            return IERC20(_getProtocolStorage().bearingTokens[_getProtocolStorage().protocols[ProtocolType.AAVE]]).balanceOf(address(this));
        } else if (block.chainid == 84532) {
            return IERC20(_getProtocolStorage().bearingTokens[_getProtocolStorage().protocols[ProtocolType.COMPOUND]]).balanceOf(address(this));
        } else {
            revert("Unsupported chain");
        }
    }

    function _protocolTotalSupply() internal view returns (uint256 totalSupply) {
         totalSupply = _getProtocolStorage().totalSupplyOfVaults[11155111];
         totalSupply += _getProtocolStorage().totalSupplyOfVaults[84532];
    }

    function _getProtocolStorage() internal pure returns (ProtocolStorage storage ps) {
        bytes32 slot = PROTOCOL_STORAGE_SLOT;
        assembly {
            ps.slot := slot
        }
    }

}
