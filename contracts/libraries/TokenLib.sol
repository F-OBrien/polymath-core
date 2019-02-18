pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../interfaces/IPoly.sol";
import "../interfaces/IDataStore.sol";

library TokenLib {
    using SafeMath for uint256;

    bytes32 internal constant WHITELIST = "WHITELIST";
    bytes32 internal constant INVESTORSKEY = 0xdf3a8dd24acdd05addfc6aeffef7574d2de3f844535ec91e8e0f3e45dba96731; //keccak256(abi.encodePacked("INVESTORS"))

    // Struct for module data
    struct ModuleData {
        bytes32 name;
        address module;
        address moduleFactory;
        bool isArchived;
        uint8[] moduleTypes;
        uint256[] moduleIndexes;
        uint256 nameIndex;
        bytes32 label;
    }

    // Structures to maintain checkpoints of balances for governance / dividends
    struct Checkpoint {
        uint256 checkpointId;
        uint256 value;
    }

    // Emit when Module is archived from the SecurityToken
    event ModuleArchived(uint8[] _types, address _module);
    // Emit when Module is unarchived from the SecurityToken
    event ModuleUnarchived(uint8[] _types, address _module);
    // Emit when Module get removed from the securityToken
    event ModuleRemoved(uint8[] _types, address _module);
    // Emit when the budget allocated to a module is changed
    event ModuleBudgetChanged(uint8[] _moduleTypes, address _module, uint256 _oldBudget, uint256 _budget);

    /**
    * @notice Archives a module attached to the SecurityToken
    * @param _moduleData Storage data
    * @param _module Address of module to archive
    */
    function archiveModule(ModuleData storage _moduleData, address _module) public {
        require(!_moduleData.isArchived, "Module archived");
        require(_moduleData.module != address(0), "Module missing");
        /*solium-disable-next-line security/no-block-members*/
        emit ModuleArchived(_moduleData.moduleTypes, _module);
        _moduleData.isArchived = true;
    }

    /**
    * @notice Unarchives a module attached to the SecurityToken
    * @param _moduleData Storage data
    * @param _module Address of module to unarchive
    */
    function unarchiveModule(ModuleData storage _moduleData, address _module) public {
        require(_moduleData.isArchived, "Module unarchived");
        /*solium-disable-next-line security/no-block-members*/
        emit ModuleUnarchived(_moduleData.moduleTypes, _module);
        _moduleData.isArchived = false;
    }

    /**
    * @notice Removes a module attached to the SecurityToken
    * @param _module address of module to unarchive
    */
    function removeModule(
        address _module,
        mapping(uint8 => address[]) storage _modules,
        mapping(address => ModuleData) storage _modulesToData,
        mapping(bytes32 => address[]) storage _names
    )
        public
    {
        require(_modulesToData[_module].isArchived, "Not archived");
        require(_modulesToData[_module].module != address(0), "Module missing");
        /*solium-disable-next-line security/no-block-members*/
        emit ModuleRemoved(_modulesToData[_module].moduleTypes, _module);
        // Remove from module type list
        uint8[] memory moduleTypes = _modulesToData[_module].moduleTypes;
        for (uint256 i = 0; i < moduleTypes.length; i++) {
            _removeModuleWithIndex(moduleTypes[i], _modulesToData[_module].moduleIndexes[i], _modules, _modulesToData);
            /* modulesToData[_module].moduleType[moduleTypes[i]] = false; */
        }
        // Remove from module names list
        uint256 index = _modulesToData[_module].nameIndex;
        bytes32 name = _modulesToData[_module].name;
        uint256 length = _names[name].length;
        _names[name][index] = _names[name][length - 1];
        _names[name].length = length - 1;
        if ((length - 1) != index) {
            _modulesToData[_names[name][index]].nameIndex = index;
        }
        // Remove from modulesToData
        delete _modulesToData[_module];
    }

    /**
    * @notice Internal - Removes a module attached to the SecurityToken by index
    */
    function _removeModuleWithIndex(
        uint8 _type,
        uint256 _index,
        mapping(uint8 => address[]) storage _modules,
        mapping(address => ModuleData) storage _modulesToData
    )
        internal
    {
        uint256 length = _modules[_type].length;
        _modules[_type][_index] = _modules[_type][length - 1];
        _modules[_type].length = length - 1;

        if ((length - 1) != _index) {
            //Need to find index of _type in moduleTypes of module we are moving
            uint8[] memory newTypes = _modulesToData[_modules[_type][_index]].moduleTypes;
            for (uint256 i = 0; i < newTypes.length; i++) {
                if (newTypes[i] == _type) {
                    _modulesToData[_modules[_type][_index]].moduleIndexes[i] = _index;
                }
            }
        }
    }

    /**
    * @notice allows owner to increase/decrease POLY approval of one of the modules
    * @param _module module address
    * @param _change change in allowance
    * @param _increase true if budget has to be increased, false if decrease
    */
    function changeModuleBudget(
        address _module,
        uint256 _change,
        bool _increase,
        address _polyToken,
        mapping(address => ModuleData) storage _modulesToData
    )
        public
    {
        require(_modulesToData[_module].module != address(0), "Module missing");
        uint256 currentAllowance = IPoly(_polyToken).allowance(address(this), _module);
        uint256 newAllowance;
        if (_increase) {
            require(IPoly(_polyToken).increaseApproval(_module, _change), "IncreaseApproval fail");
            newAllowance = currentAllowance.add(_change);
        } else {
            require(IPoly(_polyToken).decreaseApproval(_module, _change), "Insufficient allowance");
            newAllowance = currentAllowance.sub(_change);
        }
        emit ModuleBudgetChanged(_modulesToData[_module].moduleTypes, _module, currentAllowance, newAllowance);
    }

    /**
     * @notice Queries a value at a defined checkpoint
     * @param _checkpoints is array of Checkpoint objects
     * @param _checkpointId is the Checkpoint ID to query
     * @param _currentValue is the Current value of checkpoint
     * @return uint256
     */
    function getValueAt(Checkpoint[] storage _checkpoints, uint256 _checkpointId, uint256 _currentValue) public view returns(uint256) {
        //Checkpoint id 0 is when the token is first created - everyone has a zero balance
        if (_checkpointId == 0) {
            return 0;
        }
        if (_checkpoints.length == 0) {
            return _currentValue;
        }
        if (_checkpoints[0].checkpointId >= _checkpointId) {
            return _checkpoints[0].value;
        }
        if (_checkpoints[_checkpoints.length - 1].checkpointId < _checkpointId) {
            return _currentValue;
        }
        if (_checkpoints[_checkpoints.length - 1].checkpointId == _checkpointId) {
            return _checkpoints[_checkpoints.length - 1].value;
        }
        uint256 min = 0;
        uint256 max = _checkpoints.length - 1;
        while (max > min) {
            uint256 mid = (max + min) / 2;
            if (_checkpoints[mid].checkpointId == _checkpointId) {
                max = mid;
                break;
            }
            if (_checkpoints[mid].checkpointId < _checkpointId) {
                min = mid + 1;
            } else {
                max = mid;
            }
        }
        return _checkpoints[max].value;
    }

    /**
     * @notice Stores the changes to the checkpoint objects
     * @param _checkpoints is the affected checkpoint object array
     * @param _newValue is the new value that needs to be stored
     */
    function adjustCheckpoints(TokenLib.Checkpoint[] storage _checkpoints, uint256 _newValue, uint256 _currentCheckpointId) public {
        //No checkpoints set yet
        if (_currentCheckpointId == 0) {
            return;
        }
        //No new checkpoints since last update
        if ((_checkpoints.length > 0) && (_checkpoints[_checkpoints.length - 1].checkpointId == _currentCheckpointId)) {
            return;
        }
        //New checkpoint, so record balance
        _checkpoints.push(TokenLib.Checkpoint({checkpointId: _currentCheckpointId, value: _newValue}));
    }

    /**
    * @notice Keeps track of the number of non-zero token holders
    * @param _holderCount Number of current token holders
    * @param _from Sender of transfer
    * @param _to Receiver of transfer
    * @param _value Value of transfer
    * @param _balanceTo Balance of the _to address
    * @param _balanceFrom Balance of the _from address
    * @param _dataStore address of data store
    */
    function adjustInvestorCount(
        uint256 _holderCount,
        address _from,
        address _to,
        uint256 _value,
        uint256 _balanceTo,
        uint256 _balanceFrom,
        address _dataStore
    )
        public
        returns(uint256)
    {
        if ((_value == 0) || (_from == _to)) {
            return _holderCount;
        }
        // Check whether receiver is a new token holder
        if ((_balanceTo == 0) && (_to != address(0))) {
            _holderCount = _holderCount.add(1);
            IDataStore dataStore = IDataStore(_dataStore);
            if (!_isExistingInvestor(_to, dataStore)) {
                dataStore.insertAddress(INVESTORSKEY, _to);
                //KYC data can not be present if added is false and hence we can set packed KYC as uint256(1) to set added as true
                dataStore.setUint256(_getKey(WHITELIST, _to), uint256(1));
            }
        }
        // Check whether sender is moving all of their tokens
        if (_value == _balanceFrom) {
            _holderCount = _holderCount.sub(1);
        }

        return _holderCount;
    }

    function _getKey(bytes32 _key1, address _key2) internal pure returns(bytes32) {
        return bytes32(keccak256(abi.encodePacked(_key1, _key2)));
    }

    function _isExistingInvestor(address _investor, IDataStore dataStore) internal view returns(bool) {
        uint256 data = dataStore.getUint256(_getKey(WHITELIST, _investor));
        //extracts `added` from packed `whitelistData`
        return uint8(data) == 0 ? false : true;
    }
}
