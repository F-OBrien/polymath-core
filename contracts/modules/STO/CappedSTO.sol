pragma solidity ^0.4.24;

import "./ISTO.sol";
import "../../interfaces/ISecurityToken.sol";
import "openzeppelin-solidity/contracts/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./CappedSTOStorage.sol";

/**
 * @title STO module for standard capped crowdsale
 */
contract CappedSTO is CappedSTOStorage, ISTO, ReentrancyGuard {
    using SafeMath for uint256;

    ////////////
    // Events //
    ////////////

    event SetAllowBeneficialInvestments(bool _allowed);
    event SetNonAccreditedLimit(
	    address _investor,
		uint256 _limit
	);
    event SetAccredited(
	    address _investor,
		bool _accredited
	);
    /**
    * Event for token purchase logging
    * @param _purchaser who paid for the tokens
    * @param _beneficiary who got the tokens
    * @param _value amount paid for purchase in Fund Raise Type
    * @param _amount amount of tokens purchased
    */
    event TokenPurchase(
	    address indexed _purchaser,
		address indexed _beneficiary,
		uint256 _value,
		uint256 _amount
	);
	event FundsReceived(
	    address indexed _purchaser,
		address indexed _beneficiary,
        FundRaiseType _fundRaiseType,
        uint256 _receivedValue,
        uint256 _spentValue
	);
    event ReserveTokenMint(address indexed _owner, address indexed _reserveWallet, uint256 _tokens);
    event SetAddresses(
	    address indexed _wallet,
        address indexed _reserveWallet,
		address[] _usdTokens
	);
	event SetLimits(
        uint256 _nonAccreditedLimit,
        uint256 _minimumInvestment
    );
    event SetTimes(
        uint256 _startTime,
        uint256 _endTime
    );
    event SetRate(uint256 _rate);
	event SetCap(uint256 _cap);
	event SetNonAccreditedLimitEnabled (bool _enabled);
	
    ///////////////
    // Modifiers //
    ///////////////

	modifier notStarted {
        /*solium-disable-next-line security/no-block-members*/
        require(now < startTime, "STO already started");
        _;
    }
	
    modifier validETH {
        require(fundRaiseTypes[uint8(FundRaiseType.ETH)], "ETH not allowed");
        _;
    }

    modifier validPOLY {
        require(fundRaiseTypes[uint8(FundRaiseType.POLY)], "POLY not allowed");
        _;
    }

    modifier validSC(address _usdToken) {
        require(fundRaiseTypes[uint8(FundRaiseType.SC)] && usdTokenEnabled[_usdToken], "Token not allowed");
        _;
    }

    ///////////////////////
    // STO Configuration //
    ///////////////////////

    constructor (address _securityToken, address _polyAddress) public
    Module(_securityToken, _polyAddress)
    {
    }

    /*
     * @notice Function used to intialize the contract variables
     * @param _startTime Unix timestamp at which offering get started
     * @param _endTime Unix timestamp at which offering get ended
     * @param _cap Maximum No. of token base units for sale
     * @param _rate Token units a buyer gets multiplied by 10^18 per wei / base unit of POLY 
     * @param _nonAccreditedLimit Limit in fund raise type (* 10**18) for non-accredited investors
     * @param _minimumInvestment Minimun investment in fund raise type (* 10**18)
     * @param _fundRaiseTypes Type of currency used to collect the funds
     * @param _wallet Ethereum account address to hold the funds
	 * @param _reserveWallet Ethereum account where unsold Tokens will be sent if _mintReserveEnabled
	 * @param _usdTokens Array of contract addressess of the stable coins
	 * @param _nonAccreditedLimitEnabled Enables a limit for non-Accredited investors
	 * @param _mintReserveEnabled Allows unsold tokens to be minted to the reserve address
     */
    function configure(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cap,
        uint256 _rate,
        uint256 _nonAccreditedLimit,
        uint256 _minimumInvestment,
        FundRaiseType[] _fundRaiseTypes,
        address _wallet,
        address _reserveWallet,
		address[] _usdTokens,
		bool _nonAccreditedLimitEnabled,
		bool _mintReserveEnabled
	) public onlyFactory {
        require(endTime == 0, "Already configured");
        /*solium-disable-next-line security/no-block-members*/
        require(_fundRaiseTypes.length == 1, "Only one fund raise type Allowed");
        _modifyTimes(_startTime, _endTime);
        _modifyCap (_cap);
        _modifyRate (_rate);
        // NB - _setFundRaiseType must come before modifyAddresses
        _setFundRaiseType(_fundRaiseTypes);
        _modifyAddresses(_wallet, _reserveWallet, _usdTokens);
		_modifyLimits(_nonAccreditedLimit, _minimumInvestment);
		_modifyNonAccreditedLimitEnabled(_nonAccreditedLimitEnabled);
		_modifyMintReserveEnabled (_mintReserveEnabled);
    }

    /**
     * @dev Modifies fund raise types
     * @param _fundRaiseTypes Array of fund raise types to allow. Only one suppoorted
     */
    function modifyFunding(FundRaiseType[] _fundRaiseTypes) external onlyOwner notStarted{
        require(_fundRaiseTypes.length == 1, "Only one fund raise type Allowed");
        _setFundRaiseType(_fundRaiseTypes);
    }

    /**
     * @dev modifies max non accredited investment limit and overall minimum investment limit
     * @param _nonAccreditedLimit max non accredited investment limit in selected fund raise type
     * @param _minimumInvestment overall minimum investment limit in selected fund raise type
     */
    function modifyLimits(
        uint256 _nonAccreditedLimit,
        uint256 _minimumInvestment
    ) external onlyOwner notStarted {
        _modifyLimits(_nonAccreditedLimit, _minimumInvestment);
    }

    /**
     * @dev Modifies fund raise rate per token
     * @param _rate rate per token invested by 10^18 per base unit
     */
    function modifyRate(uint256 _rate) external onlyOwner notStarted {
        _modifyRate(_rate);
    }

    /**
     * @dev Modifies how many token base units this STO will be allowed to sell to investors
     * @param _cap Max number of token that can be sold by 10^18 per base unit
     */
    function modifyCap(uint256 _cap) external onlyOwner notStarted {
        _modifyCap(_cap);
    }

    /**
     * @dev Modifies STO start and end times
     * @param _startTime start time of sto
     * @param _endTime end time of sto
     */
    function modifyTimes(
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner notStarted {
        _modifyTimes(_startTime, _endTime);
    }
	
    /**
     * @dev Modifies addresses used as wallet, reserve wallet and usd token
     * @param _wallet Address of wallet where funds are sent
     * @param _reserveWallet Address of wallet where unsold tokens are sent
     * @param _usdTokens Address of usd tokens
     */
    function modifyAddresses(
        address _wallet,
        address _reserveWallet,
        address[] _usdTokens
    ) external onlyOwner {
        //can be modified even when STO started
        _modifyAddresses(_wallet, _reserveWallet, _usdTokens);
    }

    /**
     * @dev Enables or disables non accredited investor limit
     * @param _nonAccreditedLimitEnabled Whether or not nonaccredited investors will be subject to a non-Accredited Limit
     */
    function modifyNonAccreditedLimitEnabled(bool _nonAccreditedLimitEnabled) external onlyOwner notStarted {
        _modifyNonAccreditedLimitEnabled(_nonAccreditedLimitEnabled);
    }

    /**
     * @dev Enables or disables minting unsold tokens to reserve wallet
     * @param _mintReserveEnabled Whether or not unsold tokens will be minted to a reserve wallet
     */
    function modifyMintReserveEnabled(bool _mintReserveEnabled) external onlyOwner notStarted {
        _modifyMintReserveEnabled(_mintReserveEnabled);
    }	

    function _modifyLimits(
        uint256 _nonAccreditedLimit,
        uint256 _minimumInvestment
    ) internal {
        minimumInvestment = _minimumInvestment;
        nonAccreditedLimit = _nonAccreditedLimit;
        emit SetLimits(minimumInvestment, nonAccreditedLimit);
    }
    
	function _modifyRate(uint256 _rate) internal {
        require(_rate > 0, "Rate of token should be greater than 0");
        rate = _rate;
		emit SetRate (rate);
    }

    function _modifyCap(uint256 _cap) internal {
        require(_cap > 0, "Cap should be greater than 0");
        cap = _cap;
		emit SetCap (cap);
    }

    function _modifyTimes(
        uint256 _startTime,
        uint256 _endTime
    ) internal {
        /*solium-disable-next-line security/no-block-members*/
		require(_startTime >= now && _endTime > _startTime, "Invalid times");
        startTime = _startTime;
        endTime = _endTime;
        emit SetTimes(_startTime, _endTime);
    }

    function _modifyAddresses(
        address _wallet,
        address _reserveWallet,
        address[] _usdTokens
    ) internal {
        require(_wallet != address(0) && _reserveWallet != address(0), "Invalid wallet");
        wallet = _wallet;
        reserveWallet = _reserveWallet;
        _modifyUSDTokens(_usdTokens);
    }

    function _modifyUSDTokens(address[] _usdTokens) internal {
        for(uint256 i = 0; i < usdTokens.length; i++) {
            usdTokenEnabled[usdTokens[i]] = false;
        }
        usdTokens = _usdTokens;
        for(i = 0; i < _usdTokens.length; i++) {
            require(_usdTokens[i] != address(0), "Invalid USD token");
            usdTokenEnabled[_usdTokens[i]] = true;
        }
        emit SetAddresses(wallet, reserveWallet, _usdTokens);
    }

	function _modifyNonAccreditedLimitEnabled(bool _nonAccreditedLimitEnabled) internal {
        nonAccreditedLimitEnabled = _nonAccreditedLimitEnabled;
		emit SetNonAccreditedLimitEnabled (nonAccreditedLimitEnabled);
    }
	
	function _modifyMintReserveEnabled(bool _mintReserveEnabled) internal {
        mintReserveEnabled = _mintReserveEnabled;
		emit SetNonAccreditedLimitEnabled (nonAccreditedLimitEnabled);
    }
	
    ////////////////////
    // STO Management //
    ////////////////////

    /**
     * @notice Finalizes the STO and mints remaining tokens to reserve address if mint reserve is enabled
     * @notice Reserve address must be whitelisted to successfully finalize
     */
    function finalize() public onlyOwner {
        require(!isFinalized, "STO is already finalized");
        isFinalized = true;
		uint256 unsoldTokens = cap.sub(totalTokensSold);
		if ((mintReserveEnabled) && (unsoldTokens > 0)) {
            require(ISecurityToken(securityToken).mint(reserveWallet, unsoldTokens), "Error in minting");
            emit ReserveTokenMint(msg.sender, reserveWallet, unsoldTokens);
            finalAmountReturned = unsoldTokens;
		}
	}

    /**
     * @notice Modifies the list of accredited addresses
     * @param _investors Array of investor addresses to modify
     * @param _accredited Array of bools specifying accreditation status
     */
    function changeAccredited(address[] _investors, bool[] _accredited) public onlyOwner {
        require(_investors.length == _accredited.length, "Array length mismatch");
        for (uint256 i = 0; i < _investors.length; i++) {
            if (_accredited[i]) {
                investors[_investors[i]].accredited = uint8(1);
            } else {
                investors[_investors[i]].accredited = uint8(0);
            }
            _addToInvestorsList(_investors[i]);
            emit SetAccredited(_investors[i], _accredited[i]);
        }
    }

    /**
     * @notice Modifies the list of overrides for non-accredited limits in fund raise type
     * @param _investors Array of investor addresses to modify
     * @param _nonAccreditedLimit Array of uints specifying non-accredited limits
     */
    function changeNonAccreditedLimit(address[] _investors, uint256[] _nonAccreditedLimit) public onlyOwner {
        //nonAccreditedLimitOverride
        require(_investors.length == _nonAccreditedLimit.length, "Array length mismatch");
        for (uint256 i = 0; i < _investors.length; i++) {
            investors[_investors[i]].nonAccreditedLimitOverride = _nonAccreditedLimit[i];
            _addToInvestorsList(_investors[i]);

            emit SetNonAccreditedLimit(_investors[i], _nonAccreditedLimit[i]);
        }
    }

    function _addToInvestorsList(address _investor) internal {
        if (investors[_investor].seen == uint8(0)) {
            investors[_investor].seen = uint8(1);
            investorsList.push(_investor);
        }
    }

    /**
     * @notice Function to set allowBeneficialInvestments (allow beneficiary to be different to funder)
     * @param _allowBeneficialInvestments Boolean to allow or disallow beneficial investments
     */
    function changeAllowBeneficialInvestments(bool _allowBeneficialInvestments) public onlyOwner {
        require(_allowBeneficialInvestments != allowBeneficialInvestments, "Does not change value");
        allowBeneficialInvestments = _allowBeneficialInvestments;
        emit SetAllowBeneficialInvestments(allowBeneficialInvestments);
    }

    //////////////////////////
    // Investment Functions //
    //////////////////////////
	
    /**
    * @notice fallback function - assumes ETH being invested
    */
    function () external payable {
        buyWithETHRateLimited(msg.sender, 0);
    }

    function buyWithETH(address _beneficiary) external payable {
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address does not match msg.sender");
        }
		buyWithETHRateLimited(_beneficiary, 0);
    }

    function buyWithPOLY(address _beneficiary, uint256 _investedPOLY) external {
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address does not match msg.sender");
        }        buyWithPOLYRateLimited(_beneficiary, _investedPOLY, 0);
    }

    function buyWithSCToken(address _beneficiary, uint256 _investedSC, IERC20 _usdToken) external {
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address does not match msg.sender");
        }        buyWithSCRateLimited(_beneficiary, _investedSC, 0, _usdToken);
    }

    /**
      * @notice Purchase tokens using ETH
      * @param _beneficiary Address where security tokens will be sent
      * @param _minTokens Minumum number of tokens to buy or else revert
      */
    function buyWithETHRateLimited(address _beneficiary, uint256 _minTokens) public payable validETH {
        uint256 spentValue = _buyTokens(_beneficiary, msg.value, FundRaiseType.ETH, _minTokens);
        // Forward ETH to issuer wallet
        wallet.transfer(spentValue);
        // Refund excess ETH to investor wallet
        msg.sender.transfer(msg.value.sub(spentValue));
        emit FundsReceived(msg.sender, _beneficiary, FundRaiseType.ETH, msg.value, spentValue);
        _postValidatePurchase(_beneficiary, spentValue);
    }

    /**
      * @notice Purchase tokens using POLY
      * @param _beneficiary Address where security tokens will be sent
      * @param _investedPOLY Amount of POLY invested
      * @param _minTokens Minumum number of tokens to buy or else revert
      */
    function buyWithPOLYRateLimited(address _beneficiary, uint256 _investedPOLY, uint256 _minTokens) public validPOLY {
        _buyWithTokens(_beneficiary, _investedPOLY, FundRaiseType.POLY, _minTokens, polyToken);
    }

    /**
      * @notice Purchase tokens using Stable coins
      * @param _beneficiary Address where security tokens will be sent
      * @param _investedSC Amount of Stable coins invested
      * @param _minTokens Minumum number of tokens to buy or else revert
      * @param _usdToken Address of USD stable coin to buy tokens with
      */
    function buyWithSCRateLimited(address _beneficiary, uint256 _investedSC, uint256 _minTokens, IERC20 _usdToken)
        public validSC(_usdToken)
    {
        _buyWithTokens(_beneficiary, _investedSC, FundRaiseType.SC, _minTokens, _usdToken);
    }

    function _buyWithTokens(address _beneficiary, uint256 _tokenAmount, FundRaiseType _fundRaiseType, uint256 _minTokens, IERC20 _token) internal {
        require(_fundRaiseType == FundRaiseType.POLY || _fundRaiseType == FundRaiseType.SC, "Invalid raise type");
        uint256 spentValue = _buyTokens(_beneficiary, _tokenAmount, _fundRaiseType, _minTokens);
        // Modify storage
        if(address(_token) != address(polyToken))
            stableCoinsRaised[address(_token)] = stableCoinsRaised[address(_token)].add(spentValue);
        // Forward coins to issuer wallet
        require(_token.transferFrom(msg.sender, wallet, spentValue), "Transfer failed");
        emit FundsReceived(msg.sender, _beneficiary, _fundRaiseType, _tokenAmount, spentValue);
        _postValidatePurchase(_beneficiary, spentValue);
    }
	
    /**
      * @notice Low level token purchase
      * @param _beneficiary Address where security tokens will be sent
      * @param _investmentValue Amount of POLY, ETH or Stable coins invested
      * @param _fundRaiseType Fund raise type (POLY, ETH, SC)
      */
    function _buyTokens(
        address _beneficiary,
        uint256 _investmentValue,
        FundRaiseType _fundRaiseType,
		uint256 _minTokens
    )
        internal
        nonReentrant
        whenNotPaused
        returns(uint256 spentValue)
    {
        uint256 tokens;
		(tokens, spentValue) = _buyTokensChecks (_beneficiary, _investmentValue, _minTokens);
        _processPurchase(_beneficiary, tokens);
        emit TokenPurchase(msg.sender, _beneficiary, spentValue, tokens);
        _updatePurchasingState(_beneficiary, _investmentValue);
        // Modify storage
        investorInvested[_beneficiary] = investorInvested[_beneficiary].add(spentValue);
        fundsRaised[uint8(_fundRaiseType)] = fundsRaised[uint8(_fundRaiseType)].add(spentValue);
        totalTokensSold = totalTokensSold.add(tokens);
		}
	
    function _buyTokensChecks(
        address _beneficiary,
        uint256 _investmentValue,
		uint256 _minTokens
    )
        internal
        view
        returns(uint256 tokens, uint256 spentValue)
    {
        //Pre-Purchase checks
	    require(isOpen(), "STO not open");
        require(_investmentValue > 0, "No funds were sent");
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address does not match msg.sender");
        }
        require(_beneficiary != address(0), "Beneficiary address should not be 0x");
        require(_investmentValue.add(investorInvested[_beneficiary]) >= minimumInvestment, "Total investment less than minimum investment");
        // Get the maximum allowed investment value 
        uint256 allowedInvestment = _getAllowedInvestment (_beneficiary, _investmentValue);		
        // Get the number of tokens to be minted and value in fund raise type
        (tokens, spentValue) = _getTokenAmount(allowedInvestment);
        require(tokens >= _minTokens, "Insufficient tokens minted");
    }
	
	function _getAllowedInvestment (address _beneficiary, uint256 _investmentValue) internal view returns (uint256 _allowedInvestment){	
        // Accredited investors are not limited
		_allowedInvestment = _investmentValue;
        // Check for non-accredited investment cap
        if ((nonAccreditedLimitEnabled) && (investors[_beneficiary].accredited == uint8(0))) {
            uint256 investorLimit = (investors[_beneficiary].nonAccreditedLimitOverride == 0) ? nonAccreditedLimit : investors[_beneficiary].nonAccreditedLimitOverride;
            require(investorInvested[_beneficiary] < investorLimit, "Over Non-accredited investor limit");
            if (_investmentValue.add(investorInvested[_beneficiary]) > investorLimit)
                _allowedInvestment = investorLimit.sub(investorInvested[_beneficiary]);
        }
    }
		
    /**
    * @notice Overrides to extend the way in which ether is converted to tokens.
    * @param _investedAmount Value in wei to be converted into tokens
    * @return Number of tokens that can be purchased with the specified _investedAmount
    * @return Remaining amount that should be refunded to the investor
    */
    function _getTokenAmount(uint256 _investedAmount) internal view returns (uint256 _tokens, uint256 _spentValue) {
        _tokens = _investedAmount.mul(rate);
        _tokens = _tokens.div(uint256(10) ** 18);
        uint256 granularity = ISecurityToken(securityToken).granularity();
        _tokens = _tokens.div(granularity);
        _tokens = _tokens.mul(granularity);
        uint256 _remainingTokens = cap.sub(totalTokensSold);
        if (totalTokensSold.add(_tokens) > cap) {
            _tokens = _remainingTokens;
		}
        _spentValue = (_tokens.mul(uint256(10) ** 18)).div(rate);
    }
	
    /**
    * @notice Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
    * @param _beneficiary Address receiving the tokens
    * @param _tokenAmount Number of tokens to be purchased
    */
    function _processPurchase(address _beneficiary, uint256 _tokenAmount) internal {
        if (investorInvested[_beneficiary] == 0) {
            investorCount = investorCount + 1;
        }
        investorInvested[_beneficiary] = investorInvested[_beneficiary].add(_tokenAmount);

        _deliverTokens(_beneficiary, _tokenAmount);
    }

    /**
    * @notice Source of tokens.
      Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
    * @param _beneficiary Address performing the token purchase
    * @param _tokenAmount Number of tokens to be emitted
    */
    function _deliverTokens(address _beneficiary, uint256 _tokenAmount) internal {
        require(ISecurityToken(securityToken).mint(_beneficiary, _tokenAmount), "Error in minting the tokens");
    }

    /**
    * @notice Overrides for extensions that require an internal state to check for validity
      (current user contributions, etc.)
    */
    function _updatePurchasingState(
        address, /*_beneficiary*/
        uint256 _investedAmount
    ) internal pure {
        _investedAmount = 0; //yolo
    }

    /**
    * @notice Validation of an executed purchase.
      Observe state and use revert statements to undo rollback when valid conditions are not met.
    */
    function _postValidatePurchase(address /*_beneficiary*/, uint256 /*_investedAmount*/) internal pure {
      // optional override
    }	

    /////////////
    // Getters //
    /////////////

    /**
     * @notice This function returns whether or not the STO is in fundraising mode (open)
     * @return bool Whether the STO is accepting investments
     */
    function isOpen() public view returns(bool) {
        if (isFinalized)
            return false;
        /*solium-disable-next-line security/no-block-members*/
        if (now < startTime)
            return false;
        /*solium-disable-next-line security/no-block-members*/
        if (now >= endTime)
            return false;
        if (capReached())
            return false;
        return true;
    }

    /**
    * @notice Checks whether the cap has been reached.
    * @return bool Whether the cap was reached
    */
    function capReached() public view returns (bool) {
        return totalTokensSold >= cap;
    }

    /**
     * @notice Return the total no. of tokens sold
     * @return uint256 Total number of tokens sold
     */
    function getTokensSold() public view returns (uint256) {
        return totalTokensSold;
    }

    /**
     * @notice Return the usd tokens accepted by the STO
     * @return address[] usd tokens
     */
    function getUsdTokens() public view returns (address[]) {
        return usdTokens;
    }

    /**
     * @notice Return the permissions flag that are associated with STO
     */
    function getPermissions() public view returns(bytes32[]) {
        bytes32[] memory allPermissions = new bytes32[](0);
        return allPermissions;
    }
	
    /**
     * @notice Returns investor accredited & non-accredited override informatiomn
     * @return address[] list of all configured investors
     * @return bool[] whether investor is accredited
     * @return uint256[] any overrides for non-accredited limits for the investor
     */
    function getAccreditedData() external view returns (address[], bool[], uint256[]) {
        bool[] memory accrediteds = new bool[](investorsList.length);
        uint256[] memory nonAccreditedLimitOverrides = new uint256[](investorsList.length);
        uint256 i;
        for (i = 0; i < investorsList.length; i++) {
            accrediteds[i] = (investors[investorsList[i]].accredited == uint8(0)? false: true);
            nonAccreditedLimitOverrides[i] = investors[investorsList[i]].nonAccreditedLimitOverride;
        }
        return (investorsList, accrediteds, nonAccreditedLimitOverrides);
    }
	
    /**
     * @notice Return the STO details
     * @return Unixtimestamp at which offering gets start.
     * @return Unixtimestamp at which offering ends.
     * @return Number of token base units this STO will be allowed to sell to investors.
     * @return Token units a buyer gets(multiplied by 10^18) base unit of fund raise type
     * @return Amount of funds raised in Fund Raise Type
     * @return Number of individual investors this STO have.
     * @return Amount of tokens get sold. 
     * @return Fund Raise type, 0 = ETH, 1 = POLY, 2 = Stable Coin respectively
     */
    function getSTODetails() public view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint8) {
		uint8 _fundingType;
		uint256 _Raised;
		if (fundRaiseTypes[uint8(FundRaiseType.ETH)] == true) {
		    _fundingType = uint8(FundRaiseType.ETH);
			_Raised = fundsRaised[uint8(FundRaiseType.ETH)];
		} else if (fundRaiseTypes[uint8(FundRaiseType.POLY)] == true) {
		    _fundingType = uint8(FundRaiseType.POLY);
			_Raised = fundsRaised[uint8(FundRaiseType.POLY)];
        } else if (fundRaiseTypes[uint8(FundRaiseType.SC)] == true) {
		    _fundingType = uint8(FundRaiseType.SC);
			_Raised = fundsRaised[uint8(FundRaiseType.SC)];
        } else {
            revert("Incorrect funding");
        }
        return (
            startTime,
            endTime,
            cap,
            rate,
            _Raised,
            investorCount,
            totalTokensSold,
            _fundingType 
        );
    }

    /**
     * @notice This function returns the signature of configure function
     * @return bytes4 Configure function signature
     */
    function getInitFunction() public pure returns (bytes4) {
        return bytes4(keccak256("configure(uint256, uint256, uint256, uint256, uint256, uint256, uint8[], address, address, address[], bool, bool)"));
    }
}
