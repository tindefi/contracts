// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ITokenVesting{
    function createVestingSchedule(
        address _beneficiary,
        bool _revocable,
        uint256 _amount
    ) external;

    function getAdminAddress() external view returns(address);
}


/** TO-DO
    - Número de compradores en la fase (Individualizado) *
    - Target (inversión en $) para finalizar la ronda *
    - Whitelist
*/

contract ICOTinDeFi is AccessControl, Pausable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bytes32 public constant NORMAL_REFERRAL = keccak256("NORMAL_REFERRAL");
    bytes32 public constant CAPITAL_REFERRAL = keccak256("CAPITAL_REFERRAL");
    bytes32 public constant SUB_REFERRAL_CAPITAL = keccak256("SUB_REFERRAL_CAPITAL");
    bytes32 public constant SUB_REFERRAL_NORMAL = keccak256("SUB_REFERRAL_NORMAL");

    IERC20 immutable private TinDeFiToken;
    ITokenVesting private TokenVesting;
    address private vestingAddress;

    address private ICOWallet;

    struct referralInfo{
        bytes32 refType;
        address reciever;
        uint256 totalPerc;
        uint256 percTokens;
        uint256 percBUSD;
        bool active;
        string superCode;
        uint256 superCut;
    }

    struct buyInfo{
        uint256 timeStamp;
        uint256 weiPerToken;
        uint256 busdAmount;
        uint256 tinAmount;
    }

    struct raised{
        uint256 busdRaised;
        uint256 tokensBought;
    }

    mapping(uint256 => uint256) public weiPerTokenPerPhase;
    mapping(uint256 => uint256) public totalTokensSalePerPhase;
    mapping(uint256 => uint256) public tokensSoldPerPhase;
    mapping(string => referralInfo) private referrals;
    mapping(address => buyInfo[]) public buysPerUser;
    uint256 public currentPhase;
    bool private icoEnded;
    bool private buyCodeInactive;

    mapping(uint256 => uint256) public buyersPerPhase;
    uint256 public totalRaised;
    mapping(uint256 => raised) public raisedPerPhase;
    mapping(uint256 => uint256) public targetICOPerPhase;

    address private BUSD;

    event weiPerTokenChanged(uint256 indexed phase, uint256 indexed weiPerToken);
    event totalTokensSaleChanged(uint256 indexed phase, uint256 indexed totalTokensSale);
    event totalTokensSoldChanged(uint256 indexed phase, uint256 indexed totalTokensSold);
    event icoStatus(bool indexed icoStatus);
    event busdContractChanged(address indexed BUSD);
    event phaseAdded(uint256 indexed phase ,uint256 weiPerToken, uint256 indexed totalTokensSale);
    event phaseChanged(uint256 indexed newPhase);
    event tokensBought(uint256 indexed tokenAmount, address indexed buyer);

    modifier whenICOActive(){
        require(!icoEnded, "ICO has ended");
        _;
    }

    modifier buyCodeCorrect(string calldata code){
        require(buyCodeInactive || referrals[code].active, "The code provided is not correct or active");
        _;
    }

    constructor(address TinToken, address _vestingAddress, address _busdAddress, address _ICOWallet){
        TinDeFiToken = IERC20(TinToken);
        TokenVesting = ITokenVesting(_vestingAddress);
        vestingAddress = _vestingAddress;
        
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        ICOWallet = _ICOWallet;
        icoEnded = false;
        BUSD = _busdAddress;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function buyTokens(uint256 tokenAmount, string calldata buyCode) public whenICOActive buyCodeCorrect(buyCode) nonReentrant{
        require(tokensSoldPerPhase[currentPhase] + tokenAmount <= totalTokensSalePerPhase[currentPhase], "Max tokens sold for this phase surpassed");
        require(TinDeFiToken.balanceOf(vestingAddress) >= tokenAmount, "Not enough tokens in the contract, transfer more tokens to vesting contract");

        uint256 amountBUSDToBuy = tokenAmount * weiPerTokenPerPhase[currentPhase];
        referralInfo memory refInfo = referrals[buyCode];

        require(IERC20(BUSD).balanceOf(msg.sender) >= amountBUSDToBuy, "User has less BUSD than the amount he is triying to buy");

        if(refInfo.refType == CAPITAL_REFERRAL){
            buyCodeCapital(refInfo, amountBUSDToBuy, tokenAmount);
        }else if(refInfo.refType == NORMAL_REFERRAL){
            buyCodeNormal(refInfo, amountBUSDToBuy, tokenAmount);
        }else if(refInfo.refType == SUB_REFERRAL_CAPITAL){
            buyCodeNormal(refInfo, amountBUSDToBuy, tokenAmount);
        }else if(refInfo.refType == SUB_REFERRAL_NORMAL){
            buyCodeNormal(refInfo, amountBUSDToBuy, tokenAmount);
        }
        else{
            TokenVesting.createVestingSchedule(msg.sender, true, tokenAmount);
            IERC20(BUSD).transferFrom(msg.sender, ICOWallet, amountBUSDToBuy);
            buysPerUser[msg.sender].push(buyInfo(block.timestamp, weiPerTokenPerPhase[currentPhase], amountBUSDToBuy, tokenAmount));
        }
        tokensSoldPerPhase[currentPhase] += tokenAmount;
        buyersPerPhase[currentPhase] += 1;
        totalRaised += amountBUSDToBuy;
        raisedPerPhase[currentPhase] = raised(raisedPerPhase[currentPhase].busdRaised+amountBUSDToBuy, raisedPerPhase[currentPhase].tokensBought+tokenAmount);

        emit tokensBought(tokenAmount, msg.sender);
    }

    function buyCodeCapital(referralInfo memory _refInfo, uint256 _amountBusd, uint256 _tokenAmount) private{
        uint256 busdReferral = (((_amountBusd * _refInfo.totalPerc) / 100) * _refInfo.percBUSD) / 100;
        uint256 busdProtocol = _amountBusd - busdReferral;

        uint256 totalToDeductTokens = (_tokenAmount * _refInfo.totalPerc) / 100;
        uint256 tinReferral = ((totalToDeductTokens) * _refInfo.percTokens) / 100;
        uint256 tinBuyer = _tokenAmount - totalToDeductTokens;

        if(busdReferral > 0){
            IERC20(BUSD).transferFrom(msg.sender, _refInfo.reciever, busdReferral);
        }
        IERC20(BUSD).transferFrom(msg.sender, ICOWallet, busdProtocol);

        if(tinReferral > 0){
            TokenVesting.createVestingSchedule(_refInfo.reciever, true, tinReferral);
        }
        TokenVesting.createVestingSchedule(msg.sender, true, tinBuyer);

        buysPerUser[msg.sender].push(buyInfo(block.timestamp, weiPerTokenPerPhase[currentPhase], _amountBusd, tinBuyer));
    }

    function buyCodeNormal(referralInfo memory _refInfo, uint256 _amountBusd, uint256 _tokenAmount) private{
        uint256 busdReferral = (((_amountBusd * _refInfo.totalPerc) / 100) * _refInfo.percBUSD) / 100;
        uint256 busdProtocol = _amountBusd - busdReferral;

        uint256 totalToDeductTokens = (_tokenAmount * _refInfo.totalPerc) / 100;
        uint256 tinReferral = ((totalToDeductTokens) * _refInfo.percTokens) / 100;
        uint256 tinBuyer = _tokenAmount;

        if(busdReferral > 0){
            IERC20(BUSD).transferFrom(msg.sender, _refInfo.reciever, busdReferral);
        }
        IERC20(BUSD).transferFrom(msg.sender, ICOWallet, busdProtocol);

        if(tinReferral > 0){
            TokenVesting.createVestingSchedule(_refInfo.reciever, true, tinReferral);
        }
        TokenVesting.createVestingSchedule(msg.sender, true, tinBuyer);

        buysPerUser[msg.sender].push(buyInfo(block.timestamp, weiPerTokenPerPhase[currentPhase], _amountBusd, _tokenAmount));
    }

    function buyCodeSubRefCapital(referralInfo memory _refInfo, uint256 _amountBusd, uint256 _tokenAmount) private{
        referralInfo memory superInfo = referrals[_refInfo.superCode];
        require(superInfo.active, "The superior level referral is deactivated");
        uint256 busdReferral = (((_amountBusd * _refInfo.totalPerc) / 100) * _refInfo.percBUSD) / 100;
        uint256 busdProtocol = _amountBusd - busdReferral;

        uint256 totalToDeductTokens = (_tokenAmount * _refInfo.totalPerc) / 100;
        uint256 tinReferral = ((totalToDeductTokens) * _refInfo.percTokens) / 100;
        uint256 tinBuyer = _tokenAmount - totalToDeductTokens;

        if(busdReferral > 0){
            uint256 busdSuper = (busdReferral * _refInfo.superCut) / 100;
            IERC20(BUSD).transferFrom(msg.sender, superInfo.reciever, busdSuper);
            IERC20(BUSD).transferFrom(msg.sender, _refInfo.reciever, busdReferral - busdSuper);
        }
        IERC20(BUSD).transferFrom(msg.sender, ICOWallet, busdProtocol);

        if(tinReferral > 0){
            uint256 tinSuper = (tinReferral * _refInfo.superCut) / 100;
            TokenVesting.createVestingSchedule(superInfo.reciever, true, tinSuper);
            TokenVesting.createVestingSchedule(_refInfo.reciever, true, tinReferral - tinSuper);
        }
        TokenVesting.createVestingSchedule(msg.sender, true, tinBuyer);

        buysPerUser[msg.sender].push(buyInfo(block.timestamp, weiPerTokenPerPhase[currentPhase], _amountBusd, tinBuyer));
    }

    function buyCodeSubRefNormal(referralInfo memory _refInfo, uint256 _amountBusd, uint256 _tokenAmount) private{
        referralInfo memory superInfo = referrals[_refInfo.superCode];
        require(superInfo.active, "The superior level referral is deactivated");
        uint256 busdReferral = (((_amountBusd * _refInfo.totalPerc) / 100) * _refInfo.percBUSD) / 100;
        uint256 busdProtocol = _amountBusd - busdReferral;

        uint256 totalToDeductTokens = (_tokenAmount * _refInfo.totalPerc) / 100;
        uint256 tinReferral = ((totalToDeductTokens) * _refInfo.percTokens) / 100;
        uint256 tinBuyer = _tokenAmount;

        if(busdReferral > 0){
            uint256 busdSuper = (busdReferral * _refInfo.superCut) / 100;
            IERC20(BUSD).transferFrom(msg.sender, superInfo.reciever, busdSuper);
            IERC20(BUSD).transferFrom(msg.sender, _refInfo.reciever, busdReferral - busdSuper);
        }
        IERC20(BUSD).transferFrom(msg.sender, ICOWallet, busdProtocol);

        if(tinReferral > 0){
            uint256 tinSuper = (tinReferral * _refInfo.superCut) / 100;
            TokenVesting.createVestingSchedule(superInfo.reciever, true, tinSuper);
            TokenVesting.createVestingSchedule(_refInfo.reciever, true, tinReferral - tinSuper);
        }
        TokenVesting.createVestingSchedule(msg.sender, true, tinBuyer);

        buysPerUser[msg.sender].push(buyInfo(block.timestamp, weiPerTokenPerPhase[currentPhase], _amountBusd, tinBuyer));
    }

    function getCountBuysPerUser(address user) public view returns(uint256){
        return buysPerUser[user].length;
    }

    function getRate(uint256 tokenAmount) public view returns(uint256){
        uint256 amountBUSDToBuy = tokenAmount * weiPerTokenPerPhase[currentPhase];
        return amountBUSDToBuy;
    }

    function getBUSD() public view returns(uint256){
        return IERC20(BUSD).balanceOf(msg.sender);
    }

    function addReferral(string calldata _code, bytes32 _refType, address _reciever, uint256 _totalPerc, uint256 _percTokens, uint256 _percBUSD, string memory _superCode, uint256 _superCut) public onlyRole(ADMIN_ROLE){
        require(_percTokens + _percBUSD == 100, "Percent doesn't add to 100%");
        referrals[_code] = referralInfo(
                            _refType,
                            _reciever,
                            _totalPerc,
                            _percTokens,
                            _percBUSD,
                            true,
                            _superCode,
                            _superCut);
    }

    function deactivateReferral(string calldata _code) public onlyRole(ADMIN_ROLE){
        referrals[_code].active = false;
    }
    
    function getAdminAddress() external view returns(address){
        return TokenVesting.getAdminAddress();
    }

    function withdrawTokens() public onlyRole(ADMIN_ROLE){
        payable(msg.sender).transfer(address(this).balance);
        TinDeFiToken.transfer(msg.sender, TinDeFiToken.balanceOf(address(this)));
    }

    function addPhaseParams(uint256 _phase, uint256 _weiPerTokenPerPhase, uint256 _totalTokensSalePerPhase) public onlyRole(ADMIN_ROLE){
        weiPerTokenPerPhase[_phase] = _weiPerTokenPerPhase;
        totalTokensSalePerPhase[_phase] = _totalTokensSalePerPhase;
        tokensSoldPerPhase[_phase] = 0;
        targetICOPerPhase[_phase] = _totalTokensSalePerPhase * _weiPerTokenPerPhase;
        emit phaseAdded(_phase, _weiPerTokenPerPhase, _totalTokensSalePerPhase);
    }
    function changePhase(uint256 _newPhase) public onlyRole(ADMIN_ROLE){
        currentPhase = _newPhase;
        emit phaseChanged(_newPhase);
    }

    function adjustWeiPerToken(uint256 _phase, uint256 _weiPerToken) public onlyRole(ADMIN_ROLE){
        weiPerTokenPerPhase[_phase] = _weiPerToken;
        targetICOPerPhase[_phase] = totalTokensSalePerPhase[_phase] * _weiPerToken;
        emit weiPerTokenChanged(_phase, _weiPerToken);
    }

    function adjustTotalTokensSale(uint256 _phase, uint256 _totalTokensSale) public onlyRole(ADMIN_ROLE){
        totalTokensSalePerPhase[_phase] = _totalTokensSale;
        targetICOPerPhase[_phase] = _totalTokensSale * weiPerTokenPerPhase[_phase];
        emit totalTokensSaleChanged(_phase, _totalTokensSale);
    }

    function adjustTokensSoldPerPhase(uint256 _phase, uint256 _tokensSold) public onlyRole(ADMIN_ROLE){
        tokensSoldPerPhase[_phase] = _tokensSold;
        emit totalTokensSoldChanged(_phase, _tokensSold);
    }

    function endICO(bool _endICO) public onlyRole(ADMIN_ROLE){
        icoEnded = _endICO;
        emit icoStatus(icoEnded);
    }

    function changeBUSDContract(address _BUSD) public onlyRole(ADMIN_ROLE){
        BUSD = _BUSD;
        emit busdContractChanged(BUSD);
    }

    function changeVestingContract(address _newVesting) public onlyRole(ADMIN_ROLE){
        TokenVesting = ITokenVesting(_newVesting);
        vestingAddress = _newVesting;
    }

    function getWeiPerTokenPerPhase(uint256 _phase) public view returns(uint256){
        return weiPerTokenPerPhase[_phase];
    }

    function getReferral(string calldata code) public view returns(referralInfo memory){
        return referrals[code];
    }


    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) public onlyRole(DEFAULT_ADMIN_ROLE){
        _setRoleAdmin(role, adminRole);
    }

}