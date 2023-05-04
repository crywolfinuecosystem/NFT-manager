
// SPDX-License-Identifier: MIT

/**
    NFT mint and NFT farm contract.
 */

pragma solidity 0.8.10;


//Declaration of experimental ABIEncoderV2 encoder to return dynamic types
pragma experimental ABIEncoderV2;


/**
 * @dev Contract module that helps prevent reentrant calls to a function.
*/


abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


abstract contract Pausable is Context {

    event Paused(address account);

    event Unpaused(address account);

    bool private _paused;

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}



interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (uint256);    
    function transfer(address to, uint256 amount) external returns (bool);
}


contract ERC20 is Context {

    event Transfer(address indexed from, address indexed to, uint256 value);

    mapping(address => uint256) internal _balances;

    uint256 internal _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 0;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    function _create(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: create to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
}


interface IUniswapV2Router {
    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);
}



/**
 * @title Eliptic curve signature operations
 *
 * @dev Based on https://gist.github.com/axic/5b33912c6f61ae6fd96d6c4a47afde6d
 */

library ECRecovery {

  /**
   * @dev Recover signer address from a message by using his signature
   * @param hash bytes32 message, the hash is the signed message. What is recovered is the signer address.
   * @param signature bytes signature, the signature is generated using web3.eth.sign()
   */
  function recover(bytes32 hash, bytes memory signature) public pure returns (address) {
    bytes32 r;
    bytes32 s;
    uint8 v;

    //Check the signature length
    if (signature.length != 65) {
      return (address(0));
    }

    // Divide the signature in r, s and v variables
    assembly {
      r := mload(add(signature, 32))
      s := mload(add(signature, 64))
      v := byte(0, mload(add(signature, 96)))
    }

    // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
    if (v < 27) {
      v += 27;
    }

    // If the version is correct return the signer address
    if (v != 27 && v != 28) {
      return (address(0));
    } else {
      return ecrecover(hash, v, r, s);
    }
  }

}


contract CwolfNFT is ERC20, Pausable, Ownable, ReentrancyGuard {

    string public webSite;
    string public telegram;
    string public instagram;

    uint256 public timeDeployContract;
    uint256 public timeOpenNFTcontract;

    uint256 public fees = 1500000000000000;

    uint256 public amountNFTsoldByBUSD;
    uint256 public amountNFTsoldByCWOLF;
    uint256 public amountNFTsoldByBNB;
    uint256 public amountNFTsoldByOtherAddress;
    uint256 public amountCWOLFClaimed;
    uint256 public amountBUSDClaimed;
    
    address public addressCWOLF;
    address public addressBUSD   = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address public addressPCVS2  = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public addressWBNB   = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public addressOther;

    address public fundNFTs = payable(0x);
    address public authAddress = payable(0x);
    
    mapping(address => bool) private mappingAuth;

    mapping(address => uint256) public nonces;
    mapping(bytes => bool) private signatureUsed;
    mapping(bytes => infosBuy) private getInfosBySignatureMapping;

    struct infosBuy {
        address buyer;
        uint256 amount;
        uint256 wichToken;
        address smartContract;
        uint256 nonce;
        bytes signature;
        bytes32 hash;
    }

    receive() external payable { }

    constructor() ERC20("CWOLF NFT", "") {
        timeDeployContract = block.timestamp;
        mappingAuth[authAddress] = true;

        webSite = "";
        telegram = "";
        instagram = "";

        _create(address(this), 1 * (10 ** decimals()));
    }

    modifier onlyAuthorized() {
        require(_msgSender() == owner() || mappingAuth[_msgSender()] == true, "No hack here!");
        _;
    }

    function getDaysPassed() public view returns (uint256){
        return (block.timestamp - timeDeployContract) / (1 days); 
    }

    function getInfosBySignature(bytes memory signature) external view returns (infosBuy memory){
        require(_msgSender() == owner() || mappingAuth[_msgSender()], "No consultation allowed");
        return getInfosBySignatureMapping[signature]; 
    }

    //Used to update the price of NFTs in BUSD
    //returns the conversion to BUSD of the CWOLF tokens
    function getPriceCWOLFinBUSD(uint256 amount) public view returns (uint256) {

        uint256 getReturn;
        if (amount != 0) {

            address[] memory path = new address[](3);
            path[0] = addressCWOLF;
            path[1] = addressWBNB;
            path[2] = addressBUSD;

            uint256[] memory amountOutMins = IUniswapV2Router(addressPCVS2)
            .getAmountsOut(amount, path);
            getReturn = amountOutMins[path.length -1];
        }
        return getReturn;
    } 

    //returns the conversion to BUSD of the CWOLF tokens
    //used in monitoring the treasury wallet
    function getConvertBUSDtoCWOLF(uint256 amount) public view returns (uint256) {
        uint256 getReturn;
        if (amount != 0) {

            address[] memory path = new address[](3);
            path[0] = addressBUSD;
            path[1] = addressWBNB;
            path[2] = addressCWOLF;

            uint256[] memory amountOutMins = IUniswapV2Router(addressPCVS2)
            .getAmountsOut(amount, path);
            getReturn = amountOutMins[path.length -1];
        }
        return getReturn;
    } 

    function getConvertBNBtoBUSD(uint256 amount) public view returns (uint256) {
        uint256 getReturn;
        if (amount != 0) {

            address[] memory path = new address[](2);
            path[0] = addressWBNB;
            path[1] = addressBUSD;

            uint256[] memory amountOutMins = IUniswapV2Router(addressPCVS2)
            .getAmountsOut(amount, path);
            getReturn = amountOutMins[path.length -1];
        }
        return getReturn;
    } 

    function bytesLength(bytes memory signature) public pure returns (uint256) {
        return signature.length;
    }

    function hashReturn(bytes memory hash) public pure returns (bytes32,bytes32) {
        return (keccak256(abi.encodePacked(hash)),keccak256(hash));
    }

    function ckeckSignatureCrypto(
        address buyer,
        uint256 amount,
        address smartContract,
        uint256 nonce, 
        bytes memory signature) private {
        require(getInfosBySignatureMapping[signature].buyer == address(0x0), "Signature has already been used");

        require(address(this) == smartContract, "Invalid contract");
        require(signature.length == 65, "Signature length not approved");
        require(keccak256(abi.encodePacked(signature)) != 
                keccak256(abi.encodePacked("0x19457468657265756d205369676e6564204d6573736167653a0a3332")), 
                "Exploit attempt");

        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 hash = keccak256(abi.encodePacked(prefix, 
                keccak256(abi.encodePacked(smartContract,buyer,nonce,amount))));

        address recoveredAddress = ECRecovery.recover(hash, signature);
        
        require(_msgSender() == buyer, "No hacking here, no mempool bot here, motherfuck!");
        require(
            recoveredAddress == authAddress && recoveredAddress != address(0), 
            "Signature was not authorized"
            );
        require(nonces[recoveredAddress]++ == nonce, "Nonce already used");
    }

    function decodeSignature(
        address buyer,
        uint256 amount,
        address smartContract,
        uint256 nonce, 
        bytes memory signature) public pure returns 
        (address,uint256,uint256,bytes memory,bytes32,address) {

        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 hash = keccak256(abi.encodePacked(prefix, keccak256(abi.encodePacked(smartContract,buyer,nonce,amount))));
        address recoveredAddress = ECRecovery.recover(hash, signature);

        return (buyer,amount,nonce,signature,hash,recoveredAddress);
    }

    function buyNFT(
        address buyer,
        uint256 amount, 
        uint256 numbersNFTs, 
        uint256 wichToken,
        address smartContract, 
        uint256 nonce, 
        bytes memory signature) 
        external 
        nonReentrant() whenNotPaused() {

        //Redundant declaration to avoid warning message in solidity compiler
        numbersNFTs = numbersNFTs;

        ckeckSignatureCrypto(
            buyer,
            amount,
            smartContract, 
            nonce, 
            signature);

        getInfosBySignatureMapping[signature].buyer = msg.sender; 
        getInfosBySignatureMapping[signature].amount = amount; 
        getInfosBySignatureMapping[signature].wichToken = wichToken; 
        getInfosBySignatureMapping[signature].smartContract = smartContract; 
        getInfosBySignatureMapping[signature].nonce = nonce; 
        getInfosBySignatureMapping[signature].signature = signature; 

        //BUSD
        if (wichToken == 1) {
            IERC20(addressBUSD).transferFrom(msg.sender, fundNFTs, amount);
            amountNFTsoldByBUSD += amount;

        //CWOLF
        } else if (wichToken == 2) {
            IERC20(addressCWOLF).transferFrom(msg.sender, fundNFTs, amount);
            amountNFTsoldByCWOLF += amount;

        //Other
        } else if (wichToken == 3) {
            IERC20(addressOther).transferFrom(msg.sender, fundNFTs, amount);
            amountNFTsoldByOtherAddress += amount;

        }
    }

    function buyNFT_BNB(
        address buyer,
        uint256 numbersNFTs, 
        address smartContract, 
        uint256 nonce, 
        bytes memory signature) 
        external payable 
        nonReentrant() whenNotPaused() {

        //Redundant declaration to avoid warning message in solidity compiler
        numbersNFTs = numbersNFTs;

        uint256 amountBNB = msg.value;

        ckeckSignatureCrypto(
            buyer,
            amountBNB,
            smartContract, 
            nonce, 
            signature);

        getInfosBySignatureMapping[signature].buyer = msg.sender; 
        getInfosBySignatureMapping[signature].amount = amountBNB; 
        getInfosBySignatureMapping[signature].smartContract = smartContract; 
        getInfosBySignatureMapping[signature].nonce = nonce; 
        getInfosBySignatureMapping[signature].signature = signature; 

        (bool success,) = fundNFTs.call{value: amountBNB}("");
        require(success, "Failed to send BNB");
        amountNFTsoldByBNB += amountBNB;
    }


    //Only the claim account authorized in the backend that can call this function
    //here is the claim of rewards for investment quotas
    function claimRewardsTokens(
        address buyer,
        uint256 amount) external onlyAuthorized() nonReentrant() whenNotPaused() {

        IERC20(addressCWOLF).transfer(buyer, amount);

        amountCWOLFClaimed += amount;
    }

    function claimRewardsBUSD(
        address buyer,
        uint256 amount) external onlyAuthorized() nonReentrant() whenNotPaused() {

        IERC20(addressBUSD).transfer(buyer, amount);

        amountBUSDClaimed += amount;
    }

    //claimer requests the claim, which will be processed later
    function claimFeesRewards(
        address buyer) external payable nonReentrant() whenNotPaused() {

        buyer = buyer;

        require(msg.value == fees, "Invalid amount transferred");
        (bool success,) = authAddress.call{value: fees}("");
        require(success, "Failed to send BNB");
    }

    function uncheckedI (uint256 i) public pure returns (uint256) {
        unchecked { return i + 1; }
    }

    function claimManyRewards (address[] memory buyer, uint256[] memory amount) 
    external 
    onlyOwner() {

        uint256 buyerLength = buyer.length;
        for (uint256 i = 0; i < buyerLength; i = uncheckedI(i)) {  
            IERC20(addressCWOLF).transfer(buyer[i], amount[i]);
        }
    }

    function withdraw(address account, uint256 amount) public onlyOwner() {
        IERC20(addressCWOLF).transfer(account, amount);
    }

    function managerBNB () external onlyOwner() {
        uint256 amount = address(this).balance;
        payable(msg.sender).transfer(amount);
    }

    function managerERC20 (address token) external onlyOwner() {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function setStrings(
        string memory _webSite,
        string memory _telegram,
        string memory _instagram
    ) public onlyOwner() {

        webSite = _webSite;
        telegram = _telegram;
        instagram = _instagram;
    }

    function setFees (uint256 _fees) external onlyOwner() {
        fees = _fees;
    }

    //set the authorized project wallet
    function setMappingAuth(address account, bool boolean) external onlyOwner() {
        mappingAuth[account] = boolean;
        authAddress = payable(account);
    }

    function setFundNFTs(address _fundNFTs) external onlyOwner() {
        fundNFTs = _fundNFTs;
    }

    function setCWOLFAddressContract (address _addressCWOLF) external onlyOwner() {
        addressCWOLF = _addressCWOLF;
    }

    function setOtherAddress (address _addressOther) external onlyOwner() {
        addressOther = _addressOther;
    }
}
