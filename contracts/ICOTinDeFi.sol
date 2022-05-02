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

    IERC20 immutable private TinDeFiToken;
    ITokenVesting immutable private TokenVesting;
    address private vestingAddress;

    address private ICOWallet;

    mapping(uint256 => uint256) private weiPerTokenPerPhase;
    mapping(uint256 => uint256) private totalTokensSalePerPhase;
    mapping(uint256 => uint256) private tokensSoldPerPhase;
    mapping(string => bool) private buyCodes;
    uint256 public currentPhase;
    bool private icoEnded;

    mapping(uint256 => uint256) public buyersPerPhase;
    uint256 public totalRaised;

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
        require(buyCodes[code] == true, "The code provided is not correct");
        _;
    }

    constructor(address TinToken, address _vestingAddress, address _busdAddress, address _ICOWallet){
        TinDeFiToken = IERC20(TinToken);
        TokenVesting = ITokenVesting(_vestingAddress);
        vestingAddress = _vestingAddress;
        
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

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

        require(IERC20(BUSD).balanceOf(msg.sender) >= amountBUSDToBuy, "User has less BUSD than the amount he is triying to buy");
        IERC20(BUSD).transferFrom(msg.sender, ICOWallet, amountBUSDToBuy);

        tokensSoldPerPhase[currentPhase] += tokenAmount;
        buyersPerPhase[currentPhase] += 1;
        totalRaised += amountBUSDToBuy;
        TokenVesting.createVestingSchedule(msg.sender, true, tokenAmount);

        emit tokensBought(tokenAmount, msg.sender);
    }

    function getRate(uint256 tokenAmount) public view returns(uint256){
        uint256 amountBUSDToBuy = tokenAmount * weiPerTokenPerPhase[currentPhase];
        return amountBUSDToBuy;
    }

    function getBUSD() public view returns(uint256){
        return IERC20(BUSD).balanceOf(msg.sender);
    }

    function addBuyCode(string calldata _code) public onlyRole(ADMIN_ROLE){
        buyCodes[_code] = true;
    }

    function removeBuyCode(string calldata _code) public onlyRole(ADMIN_ROLE){
        buyCodes[_code] = false;
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
        emit phaseAdded(_phase, _weiPerTokenPerPhase, _totalTokensSalePerPhase);
    }
    function changePhase(uint256 _newPhase) public onlyRole(ADMIN_ROLE){
        currentPhase = _newPhase;
        emit phaseChanged(_newPhase);
    }

    function adjustWeiPerToken(uint256 _phase, uint256 _weiPerToken) public onlyRole(ADMIN_ROLE){
        weiPerTokenPerPhase[_phase] = _weiPerToken;
        emit weiPerTokenChanged(_phase, _weiPerToken);
    }

    function adjustTotalTokensSale(uint256 _phase, uint256 _totalTokensSale) public onlyRole(ADMIN_ROLE){
        totalTokensSalePerPhase[_phase] = _totalTokensSale;
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

    function getWeiPerTokenPerPhase(uint256 _phase) public view returns(uint256){
        return weiPerTokenPerPhase[_phase];
    }

}