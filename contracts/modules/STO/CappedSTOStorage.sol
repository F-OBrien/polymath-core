pragma solidity ^0.4.24;

/**
 * @title Contract used to store layout for the CappedSTO storage
 */
contract CappedSTOStorage {

    /////////////
    // Storage //
    /////////////

    // How many token base units this STO will be allowed to sell to investors
    // 1 full token = 10^decimals_of_token base units
    uint256 public cap; 

    // How many token units a buyer gets per base unit of Fund Raise Type (i.e. ETH/POLY/SC) (multiplied by 10^18)
    // If rate is 10^18, buyer will get 1 token unit for every ETH/POLY/SC token.
    uint256 public rate;

    // Determine whether users can invest on behalf of a beneficiary
    bool public allowBeneficialInvestments = false;

    // Whether or not the STO has been finalized
    bool public isFinalized;

    // Address of issuer reserve wallet for unsold tokens
    address public reserveWallet;	
	
    // List of stable coin addresses
    address[] public usdTokens;

    // Amount of stable coins raised
    mapping (address => uint256) public stableCoinsRaised;
	
    // Amount in the selected fund raise type invested by each investor
    mapping (address => uint256) public investorInvested;

    // List of accredited investors
    mapping (address => bool) public accredited;

    // List of active stable coin addresses
    mapping (address => bool) public usdTokenEnabled;

    // Default limit in fund raise type for non-accredited investors multiplied by 10**18
    uint256 public nonAccreditedLimit;

 	// Whether or not non-accredited investors will be subject to a non-Accredited Limit 
	bool public nonAccreditedLimitEnabled;

    // Overrides for default limit in fund raise type for non-accredited investors multiplied by 10**18
    mapping (address => uint256) public nonAccreditedLimitOverride;

    // Minimum investable amount in FundRaiseType (ETH/POLY/SC)
    uint256 public minimumInvestment;

	// Whether or not unsold tokens will be minted to a reserve wallet 
	bool public mintReserveEnabled;

    // Final amount of tokens returned to issuer
    uint256 public finalAmountReturned;
	
}