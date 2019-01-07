pragma solidity ^0.4.24;

import "./POLYCappedSTO.sol";
import "../ModuleFactory.sol";
import "../../libraries/Util.sol";

/**
 * @title Factory for deploying POLYCappedSTO module
 */
contract POLYCappedSTOFactory is ModuleFactory {

    /**
     * @notice Constructor
     * @param _polyAddress Address of the polytoken
     */
    constructor (address _polyAddress, uint256 _setupCost, uint256 _usageCost, uint256 _subscriptionCost) public
    ModuleFactory(_polyAddress, _setupCost, _usageCost, _subscriptionCost)
    {
        version = "1.0.0";
        name = "POLYCappedSTO";
        title = "POLY - Capped STO";
        //NEED TO UPDATE DESCRIPTION
        description = "This smart contract creates a maximum number of tokens (i.e. hard cap) which the total aggregate of tokens acquired by all investors cannot exceed. Security tokens are sent to the investor upon reception of the funds (POLY). This STO supports options for a minimum investment limit for all investors, maximum investment limit for non-accredited investors and an option to mint unsold tokens to a reserve wallet upon termination of the offering.";
        compatibleSTVersionRange["lowerBound"] = VersionUtils.pack(uint8(0), uint8(0), uint8(0));
        compatibleSTVersionRange["upperBound"] = VersionUtils.pack(uint8(0), uint8(0), uint8(0));
    }

     /**
     * @notice Used to launch the Module with the help of factory
     * @return address Contract address of the Module
     */
    function deploy(bytes _data) external returns(address) {
        if(setupCost > 0)
            require(polyToken.transferFrom(msg.sender, owner, setupCost), "Sufficent Allowance is not provided");
        //Check valid bytes - can only call module init function
        POLYCappedSTO cappedSTO = new POLYCappedSTO(msg.sender, address(polyToken));
        //Checks that _data is valid (not calling anything it shouldn't)
        require(Util.getSig(_data) == cappedSTO.getInitFunction(), "Invalid data");
        /*solium-disable-next-line security/no-low-level-calls*/
        require(address(cappedSTO).call(_data), "Unsuccessfull call");
        /*solium-disable-next-line security/no-block-members*/
        emit GenerateModuleFromFactory(address(cappedSTO), getName(), address(this), msg.sender, setupCost, now);
        return address(cappedSTO);
    }

    /**
     * @notice Type of the Module factory
     */
    function getTypes() external view returns(uint8[]) {
        uint8[] memory res = new uint8[](1);
        res[0] = 3;
        return res;
    }

    /**
     * @notice Returns the instructions associated with the module
     */
    function getInstructions() external view returns(string) {
        /*solium-disable-next-line max-len*/
        // NEED TO UPDATE INSTRUCTIONS
        return "Initialises a POLY capped STO. Init parameters are _startTime (time STO starts), _endTime (time STO ends), _cap (cap in tokens for STO), _rate (POLY to token rate), _nonAccreditedLimit (maximum investment for non-accredited investors), _minimumInvestment (required minimum investment)  _wallet (address which will receive funds), _reserveWallet (address which will receive unsold tokens if _mintReserveEnabled), _nonAccreditedLimitEnabled (Enables the non-accredited investor investment limit), bool _mintReserveEnabled (enables minting unsold tokens to the reserve wallet)";
    }

    /**
     * @notice Get the tags related to the module factory
     */
    function getTags() external view returns(bytes32[]) {
        bytes32[] memory availableTags = new bytes32[](3);
        availableTags[0] = "Capped";
        availableTags[1] = "Non-refundable";
        availableTags[2] = "POLY";
        return availableTags;
    }

}
