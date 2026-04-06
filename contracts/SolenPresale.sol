// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBEP20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/**
 * @title SolenPresale
 * @notice Accepts USDT (BEP20) and distributes pSOLEN at a fixed rate.
 *
 *   Rate:  1 pSOLEN = 0.015 USDT
 *          1 USDT   = 66.666... pSOLEN
 *
 *   Math:  tokensOut = usdtIn * TOKEN_RATE / RATE_DENOM
 *          where TOKEN_RATE = 200, RATE_DENOM = 3
 *          (equivalent to dividing by 0.015)
 *
 *   Owner can:
 *     - pause / unpause sales
 *     - withdraw collected USDT
 *     - withdraw unsold pSOLEN
 *     - update hard cap, per-wallet min/max
 */
contract SolenPresale {
    // --- Constants ---
    uint256 public constant TOKEN_RATE  = 200;   // numerator
    uint256 public constant RATE_DENOM  = 3;     // denominator  (200/3 ≈ 66.667 tokens per USDT)

    // --- Immutables ---
    IBEP20  public immutable usdt;
    IBEP20  public immutable pSolen;
    address public immutable owner;

    // --- Config (owner-adjustable) ---
    uint256 public hardCap     = 250_000 * 1e18;   // 250K USDT
    uint256 public minBuy      = 10 * 1e18;         // 10 USDT minimum
    uint256 public maxPerWallet = 250_000 * 1e18;   // no per-wallet cap (same as hard cap)
    uint256 public endTime;                          // presale end timestamp
    bool    public paused;

    // --- State ---
    uint256 public totalRaised;
    mapping(address => uint256) public contributed;

    // --- Events ---
    event TokensPurchased(address indexed buyer, uint256 usdtAmount, uint256 tokenAmount);
    event USDTWithdrawn(address indexed to, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);
    event Paused(bool state);
    event HardCapUpdated(uint256 newCap);
    event LimitsUpdated(uint256 newMin, uint256 newMax);
    event EndTimeUpdated(uint256 newEndTime);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _usdt, address _pSolen, uint256 _endTime) {
        require(_usdt   != address(0), "zero usdt");
        require(_pSolen != address(0), "zero pSolen");
        require(_endTime > block.timestamp, "end time must be in the future");
        usdt   = IBEP20(_usdt);
        pSolen = IBEP20(_pSolen);
        owner  = msg.sender;
        endTime = _endTime;
    }

    // --- Public ---

    /// @notice Buy pSOLEN with USDT. Caller must approve USDT first.
    function buy(uint256 usdtAmount) external {
        require(!paused, "presale paused");
        require(block.timestamp < endTime, "presale ended");
        require(usdtAmount >= minBuy, "below minimum");
        require(contributed[msg.sender] + usdtAmount <= maxPerWallet, "exceeds wallet limit");
        require(totalRaised + usdtAmount <= hardCap, "hard cap reached");

        uint256 tokenAmount = (usdtAmount * TOKEN_RATE) / RATE_DENOM;
        require(pSolen.balanceOf(address(this)) >= tokenAmount, "insufficient pSOLEN supply");

        contributed[msg.sender] += usdtAmount;
        totalRaised += usdtAmount;

        // Pull USDT from buyer → this contract
        require(usdt.transferFrom(msg.sender, address(this), usdtAmount), "USDT transfer failed");

        // Send pSOLEN to buyer
        require(pSolen.transfer(msg.sender, tokenAmount), "pSOLEN transfer failed");

        emit TokensPurchased(msg.sender, usdtAmount, tokenAmount);
    }

    // --- Views ---

    /// @notice Calculate how many pSOLEN for a given USDT amount.
    function estimateTokens(uint256 usdtAmount) external pure returns (uint256) {
        return (usdtAmount * TOKEN_RATE) / RATE_DENOM;
    }

    /// @notice Remaining USDT until hard cap.
    function remainingCap() external view returns (uint256) {
        return hardCap > totalRaised ? hardCap - totalRaised : 0;
    }

    /// @notice pSOLEN balance available in this contract.
    function tokensAvailable() external view returns (uint256) {
        return pSolen.balanceOf(address(this));
    }

    // --- Owner ---

    function withdrawUSDT() external onlyOwner {
        uint256 bal = usdt.balanceOf(address(this));
        require(bal > 0, "nothing to withdraw");
        require(usdt.transfer(owner, bal), "withdraw failed");
        emit USDTWithdrawn(owner, bal);
    }

    function withdrawTokens(uint256 amount) external onlyOwner {
        require(pSolen.transfer(owner, amount), "withdraw failed");
        emit TokensWithdrawn(owner, amount);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    function setHardCap(uint256 _cap) external onlyOwner {
        hardCap = _cap;
        emit HardCapUpdated(_cap);
    }

    function setLimits(uint256 _min, uint256 _max) external onlyOwner {
        minBuy = _min;
        maxPerWallet = _max;
        emit LimitsUpdated(_min, _max);
    }

    function setEndTime(uint256 _endTime) external onlyOwner {
        endTime = _endTime;
        emit EndTimeUpdated(_endTime);
    }
}
