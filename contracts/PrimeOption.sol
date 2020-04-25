pragma solidity ^0.6.2;

/**
 * @title Primitive's Base ERC-20 Option
 * @author Primitive
 */

import "./PrimeInterface.sol";
import "./controller/Instruments.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PrimeOption is ERC20, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public constant DENOMINATOR = 1 ether;

    address public factory;
    address public tokenR;

    uint256 public marketId;
    uint256 public cacheU;
    uint256 public cacheS;
    uint256 public cacheR;
    
    Instruments.PrimeOption public option;

    function getCaches() public view returns (uint256 _cacheU, uint256 _cacheS, uint256 _cacheR) {
        _cacheU = cacheU;
        _cacheS = cacheS;
        _cacheR = cacheR;
    }

    event Mint(address indexed from, uint256 primes, uint256 redeems);
    event Swap(address indexed from, uint256 amount, uint256 strikes);
    event Redeem(address indexed from, uint256 amount);
    event Close(address indexed from, uint256 amount);
    event Fund(uint256 cacheU, uint256 cacheS, uint256 cacheR);

    constructor (
        string memory name,
        string memory symbol,
        uint256 _marketId,
        address tokenU,
        address tokenS,
        uint256 ratio,
        uint256 expiry
    ) 
        public
        ERC20(name, symbol)
    {
        marketId = _marketId;
        factory = msg.sender;
        option = Instruments.PrimeOption(
            tokenU,
            tokenS,
            ratio,
            expiry
        );
    }

    modifier notExpired {
        require(option.expiry >= block.timestamp, "ERR_EXPIRED");
        _;
    }

    receive() external payable {}

    function setRPulp(address _redeem) public returns (bool) {
        require(msg.sender == factory, 'ERR_NOT_OWNER');
        tokenR = _redeem;
        return true;
    }

    /**
     * @dev Sets the cache balances to new values.
     */
    function _fund(uint256 balanceU, uint256 balanceS, uint256 balanceR) private {
        cacheU = balanceU;
        cacheS = balanceS;
        cacheR = balanceR;
        emit Fund(balanceU, balanceS, balanceR);
    }

    /**
     * @dev Mint Primes by depositing tokenU.
     * @notice Also mints Prime Redeem tokens. Calls msg.sender with transferFrom. 
     * @param amount Quantity of Prime options to mint.
     */
    function safeMint(uint256 amount) external nonReentrant returns (uint256 primes, uint256 redeems) {
        verifyBalance(IERC20(option.tokenU).balanceOf(msg.sender), amount, "ERR_BAL_UNDERLYING");
        IERC20(option.tokenU).transferFrom(msg.sender, address(this), amount);
        (primes, redeems) = mint();
    }

    /**
     * @dev Core function to mint new Prime ERC-20 Options.
     * @notice Checks the balance of the contract against the token's 'cache',
     * The difference is the amount of tokenU sent into the contract.
     * The difference determines how many Primes and Redeems to mint.
     * Only callable when the option is not expired.
     */
    function mint() public nonReentrant notExpired returns (uint256 primes, uint256 redeems) {

        // Current balance of tokenU.
        uint256 balanceU = IERC20(option.tokenU).balanceOf(address(this));

        // Mint primes equal to the difference between current balance and previous balance of tokenU.
        primes = balanceU.sub(cacheU);

        // Mint Redeems equal to tokenU * ratio
        redeems = primes.mul(option.ratio).div(DENOMINATOR);

        // Mint the tokens.
        require(primes > 0 && redeems > 0, "ERR_ZERO");
        IPrimeRedeem(tokenR).mint(msg.sender, redeems);
        _mint(msg.sender, primes);

        // Update the caches.
        _fund(balanceU, cacheS, cacheR);
        emit Mint(msg.sender, primes, redeems);
    }

    /**
     * @dev Swaps tokenS to tokenU using Ratio as the exchange rate.
     * @notice Burns Prime, contract receives tokenS, user receives tokenU. 
     * Calls msg.sender with transferFrom. 
     * @param amount Quantity of Primes to use to swap.
     */
    function safeSwap(uint256 amount) external nonReentrant returns (uint256 inTokenS, uint256 outTokenU) {
        verifyBalance(balanceOf(msg.sender), amount, "ERR_BAL_PRIME");
        uint256 strikes = amount.mul(option.ratio).div(DENOMINATOR);
        IERC20(option.tokenS).transferFrom(msg.sender, address(this), strikes);
        (inTokenS, outTokenU) = swap();
    }

    /**
     * @dev Swap tokenS to tokenU at a rate of tokenS / ratio = tokenU.
     * @notice Checks the balance against the previously cached balance.
     * The difference is the amount of tokenS sent into the contract.
     * The difference determines how much tokenU to send out.
     * Only callable when the option is not expired.
     */
    function swap() public nonReentrant notExpired returns (uint256 inTokenS, uint256 outTokenU) {

        // Current balances.
        uint256 balanceS = IERC20(option.tokenS).balanceOf(address(this));
        uint256 balanceU = IERC20(option.tokenU).balanceOf(address(this));

        // Differences between tokenS balance less cache.
        inTokenS = balanceS.sub(cacheS);

        // inTokenS / ratio = outTokenU
        outTokenU = inTokenS.mul(DENOMINATOR).div(option.ratio);

        // Burn the Prime options at a 1:1 ratio to outTokenU.
        _burn(msg.sender, outTokenU);

        // Transfer the swapped tokenU to msg.sender.
        IERC20(option.tokenU).transfer(msg.sender, outTokenU);

        // Current balances.
        balanceS = IERC20(option.tokenS).balanceOf(address(this));
        balanceU = IERC20(option.tokenU).balanceOf(address(this));

        // Update the cached balances.
        _fund(balanceU, balanceS, cacheR);
        emit Swap(msg.sender, outTokenU, inTokenS);
    }

    /**
     * @dev Burns Prime Redeem tokens to withdraw available tokenS.
     * @param amount Quantity of Prime Redeem to spend.
     */
    function safeRedeem(uint256 amount) external nonReentrant returns (uint256 inTokenR) {
        uint256 balanceR = IPrimeRedeem(tokenR).balanceOf(msg.sender);
        verifyBalance(balanceR, amount, "ERR_BAL_REDEEM");
        IPrimeRedeem(tokenR).transferFrom(msg.sender, address(this), amount);
        (inTokenR) = redeem();
    }

    /**
     * @dev Burns tokenR to withdraw tokenS at a ratio of 1:1.
     * @notice Should only be called by a contract that checks the balanaces to be sent correctly.
     * Checks the tokenR balance against the previously cached tokenR balance.
     * The difference is the amount of tokenR sent into the contract.
     * The difference is equal to the amount of tokenS sent out.
     * Callable even when expired.
     */
    function redeem() public nonReentrant returns (uint256 inTokenR) {
        address _tokenS = option.tokenS;
        address _tokenR = tokenR;

        // Current balances.
        uint256 balanceS = IERC20(_tokenS).balanceOf(address(this));
        uint256 balanceR = IERC20(_tokenR).balanceOf(address(this));

        // Difference between tokenR balance and cache.
        inTokenR = balanceR.sub(cacheR);
        verifyBalance(balanceS, inTokenR, "ERR_BAL_STRIKE");

        // Burn tokenR in the contract. Send tokenS to msg.sender.
        IPrimeRedeem(_tokenR).burn(address(this), inTokenR);
        IERC20(_tokenS).transfer(msg.sender, inTokenR);

        // Current balances.
        balanceS = IERC20(_tokenS).balanceOf(address(this));
        balanceR = IERC20(_tokenR).balanceOf(address(this));

        // Update the cached balances.
        _fund(cacheU, balanceS, balanceR);
        emit Redeem(msg.sender, inTokenR);
    }

    /**
     * @dev Burn Prime and Prime Redeem tokens to withdraw tokenU.
     * @notice Takes paramter for quantity of Primes to burn. 
     * The Prime Redeems to burn is equal to the Primes * ratio.
     * @param amount Quantity of Primes to burn.
     */
    function safeClose(
        uint256 amount
    ) 
        external
        nonReentrant
        returns (uint256 inTokenR, uint256 inTokenP, uint256 outTokenU)
    {
        uint256 balanceR = IPrimeRedeem(tokenR).balanceOf(msg.sender);
        uint256 balanceP = balanceOf(msg.sender);
        uint256 strikes = amount.mul(option.ratio).div(DENOMINATOR);
        verifyBalance(balanceR, strikes, "ERR_BAL_REDEEM");
        verifyBalance(balanceP, amount, "ERR_BAL_PRIME");
        IPrimeRedeem(tokenR).transferFrom(msg.sender, address(this), strikes);
        transferFrom(msg.sender, address(this), amount);
        (inTokenR, inTokenP, outTokenU) = close();
    }

    /**
     * @dev Burn Prime and Prime Redeem tokens to withdraw tokenU.
     * @notice Checks the balances against the previously cached balances.
     * The difference between the tokenR balance and cache is the inTokenR.
     * The balance of tokenP is equal to the inTokenP.
     * The outTokenU is equal to the inTokenR / ratio.
     * The contract requires the inTokenP >= outTokenU and the balanceU >= outTokenU.
     * The contract burns the inTokenR and inTokenP amounts.
     * The contract sends outTokenU to msg.sender.
     */
    function close()
        public
        nonReentrant
        returns (uint256 inTokenR, uint256 inTokenP, uint256 outTokenU)
    {
        // Stores addresses locally for gas savings.
        address _tokenU = option.tokenU;
        address _tokenR = tokenR;

        // Current balances.
        uint256 balanceU = IERC20(_tokenU).balanceOf(address(this));
        uint256 balanceR = IPrimeRedeem(_tokenR).balanceOf(address(this));
        uint256 balanceP = balanceOf(address(this));

        // Differences between current and cached balances.
        inTokenR = balanceR.sub(cacheR);

        // Assumes the cached balance is 0.
        // This is because the close function burns the Primes received.
        // Only external transfers will be able to send Primes to this contract.
        // Close() is the only function that checks for the Primes balance.
        inTokenP = balanceP;

        // The quantity of tokenU to send out it still determined by the amount of inTokenR.
        // This outTokenU amount is checked against inTokenP.
        // inTokenP must be greater than or equal to outTokenU.
        // balanceP must be greater than or equal to outTokenU.
        // Neither inTokenR or inTokenP can be zero.
        outTokenU = inTokenR.mul(DENOMINATOR).div(option.ratio);
        require(inTokenR > 0 && inTokenP > 0, "ERR_ZERO");
        require(inTokenP >= outTokenU && balanceU >= outTokenU, "ERR_BAL_UNDERLYING");
        
        // Burn inTokenR and inTokenP.
        IPrimeRedeem(_tokenR).burn(address(this), inTokenR);        
        _burn(address(this), inTokenP);

        // Send outTokenU to user.
        // User does not receive extra tokenU if there was extra tokenP in the contract.
        // User receives outTokenU proportional to inTokenR.
        // Amount of inTokenP must be greater than outTokenU.
        // If tokenP was sent to the contract from an external call,
        // a user could send only tokenR and receive the proportional amount of tokenU,
        // as long as the amount of outTokenU is less than or equal to
        // the balance of tokenU and tokenP.
        IERC20(_tokenU).transfer(msg.sender, outTokenU);

        // Current balances of tokenU and tokenR.
        balanceU = IERC20(_tokenU).balanceOf(address(this));
        balanceR = IPrimeRedeem(_tokenR).balanceOf(address(this));

        // Update the cached balances.
        _fund(balanceU, cacheS, balanceR);
        emit Close(msg.sender, outTokenU);
    }

    function verifyBalance(
        uint256 balance,
        uint256 minBalance,
        string memory errorCode
    ) internal pure {
        minBalance == 0 ? 
            require(balance > minBalance, errorCode) :
            require(balance >= minBalance, errorCode);
    }

    function tokenS() public view returns (address) {
        return option.tokenS;
    }

    function tokenU() public view returns (address) {
        return option.tokenU;
    }

    function ratio() public view returns (uint256) {
        return option.ratio;
    }

    function expiry() public view returns (uint256) {
        return option.expiry;
    }

    /**
     * @dev Utility function to get the max withdrawable tokenS amount of msg.sender.
     */
    function maxDraw() public view returns (uint256 draw) {
        uint256 balanceR = IPrimeRedeem(tokenR).balanceOf(msg.sender);
        cacheS > balanceR ?
            draw = balanceR :
            draw = cacheS;
    }
}