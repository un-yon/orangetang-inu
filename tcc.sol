// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
            address token, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline
            ) external payable returns (
                uint256 amountToken, uint256 amountETH, uint256 liquidity
                );

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
            uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline
            ) external;
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) { return msg.sender; }
}

contract Ownable is Context {
    address private _owner;
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
    }
    function owner() public view returns (address) { return _owner; }
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner.");
        _;
    }
    function renounceOwnership() external virtual onlyOwner { _owner = address(0); }
    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address.");
        _owner = newOwner;
    }
}

contract TCC is IERC20, Ownable {
    IRouter public uniswapV2Router;
    address public uniswapV2Pair;
    string private constant _name =  "Travel Club Crypto";
    string private constant _symbol = "$TCC";
    uint8 private constant _decimals = 18;
    mapping (address => uint256) private balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 private constant _totalSupply = 100000000 * 10**18;      // 100 million
    uint256 public maxWalletAmount = _totalSupply * 2 / 100;         // 2%
    uint256 public maxTxAmount = _totalSupply * 2 / 100;             // 2%
    mapping (address => bool) private _isExcludedFromMaxWalletLimit;
    mapping (address => bool) private _isExcludedFromMaxTransactionLimit;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isWhitelisted;
    uint8 public buyTax = 5;
    uint8 public sellTax = 10;
    uint8 private lpRatio = 33;         // 5%
    uint8 private marketingRatio = 46;  // 7%
    uint8 private devRatio = 21;        // 3%
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD;
    address public constant marketingWallet = payable(0xc0408339132Aa7197701C2eCE6fF899de30ECBa7);
    address public constant devWallet = payable(0x8c802009dF25f7a3979Ebcf4b332aEf1E3ff59E6);
    bool private tradingOpen = false;

    constructor() {
        IRouter _uniswapV2Router = IRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH() );
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[marketingWallet] = true;
        _isExcludedFromFee[devWallet] = true;
        _isExcludedFromFee[deadWallet] = true;
        _isExcludedFromMaxWalletLimit[owner()] == true;
        _isExcludedFromMaxWalletLimit[address(uniswapV2Router)] = true;
        _isExcludedFromMaxWalletLimit[uniswapV2Pair] = true;
        _isExcludedFromMaxWalletLimit[address(this)] = true;
        _isExcludedFromMaxWalletLimit[marketingWallet] = true;
        _isExcludedFromMaxWalletLimit[devWallet] = true;
        _isExcludedFromMaxWalletLimit[deadWallet] = true;
        _isExcludedFromMaxTransactionLimit[owner()] = true;
        _isExcludedFromMaxTransactionLimit[address(uniswapV2Router)] = true;
        _isExcludedFromMaxTransactionLimit[uniswapV2Pair] = true;
        _isExcludedFromMaxTransactionLimit[address(this)] = true;
        _isExcludedFromMaxTransactionLimit[marketingWallet] = true;
        _isExcludedFromMaxTransactionLimit[devWallet] = true;
        _isExcludedFromMaxTransactionLimit[deadWallet] = true;
        _isWhitelisted[owner()] = true;
        balances[owner()] = _totalSupply;
        emit Transfer(address(0), owner(), _totalSupply);
    }

    receive() external payable {} // so the contract can receive eth

    function setFees(uint8 newBuyTax, uint8 newSellTax) external onlyOwner {
        require(newBuyTax <= 10 && newSellTax <= 10, "fees must be <=10%");
        require(newBuyTax != buyTax || newSellTax != sellTax, "new fees cannot be the same as old fees");
        buyTax = newBuyTax;
        sellTax = newSellTax;
    }

    function setRatios(uint8 newLpRatio, uint8 newMarketingRatio, uint8 newDevRatio) external onlyOwner {
        require(newLpRatio + newMarketingRatio + newDevRatio == 100, "ratios must add up to 100");
        lpRatio = newLpRatio;
        marketingRatio = newMarketingRatio;
        devRatio = newDevRatio;
    }

    function openTrading() external onlyOwner {
        require(!tradingOpen, "trading is already open");
        tradingOpen = true;
    }

    function addWL(address newAddress) external onlyOwner {
        require(!_isWhitelisted[newAddress], "address already added");
        _isWhitelisted[newAddress] = true;
    }

    function withdrawStuckETH() external onlyOwner {
        require(address(this).balance > 0, "cannot send more than contract balance");
        uint256 amount = address(this).balance;
        (bool success,) = address(owner()).call{value : amount}("");
        require(success, "error withdrawing ETH from contract");
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender,address recipient,uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        require(amount <= _allowances[sender][msg.sender], "ERC20: transfer amount exceeds allowance.");
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool){
        _approve(msg.sender,spender,_allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        require(subtractedValue <= _allowances[msg.sender][spender], "ERC20: decreased allownace below zero.");
        _approve(msg.sender,spender,_allowances[msg.sender][spender] - subtractedValue);
        return true;
    }

    function _approve(address owner, address spender,uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
    }

    function name() external pure returns (string memory) { return _name; }
    function symbol() external pure returns (string memory) { return _symbol; }
    function decimals() external view virtual returns (uint8) { return _decimals; }
    function totalSupply() external pure override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return balances[account]; }
    function allowance(address owner, address spender) external view override returns (uint256) { return _allowances[owner][spender]; }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "cannot transfer from the zero address.");
        require(to != address(0), "cannot transfer to the zero address.");
        require(amount > 0, "transfer amount must be greater than zero.");
        require(amount <= balanceOf(from), "cannot transfer more than balance.");
        require(tradingOpen || _isWhitelisted[to] || (_isWhitelisted[from] && to == uniswapV2Pair), "trading is not open yet");
        if ((from == address(uniswapV2Pair) && !_isExcludedFromMaxTransactionLimit[to]) ||
                (to == address(uniswapV2Pair) && !_isExcludedFromMaxTransactionLimit[from])) {
            require(amount <= maxTxAmount, "transfer amount exceeds the maxTxAmount.");
        }
        if (!_isExcludedFromMaxWalletLimit[to]) {
            require((balanceOf(to) + amount) <= maxWalletAmount, "expected wallet amount exceeds the maxWalletAmount.");
        }
        if ( (_isExcludedFromFee[from] || _isExcludedFromFee[to]) ||
                (from != uniswapV2Pair && to != uniswapV2Pair) ) {
            balances[from] -= amount;
            balances[to] += amount;
            emit Transfer(from, to, amount);
        } else {
            balances[from] -= amount;
            if (from == uniswapV2Pair) { // buy
                balances[address(this)] += amount * buyTax / 100;
                emit Transfer(from, address(this), amount * buyTax / 100);
                balances[to] += amount - (amount * buyTax / 100);
                emit Transfer(from, to, amount - (amount * buyTax / 100));
            } else { // sell
                balances[address(this)] += amount * sellTax / 100;
                emit Transfer(from, address(this), amount * sellTax / 100);
                if (balanceOf(address(this)) > _totalSupply / 4000) { // .025% threshold for swapping
                    uint256 liquidityAmount = balanceOf(address(this)) * lpRatio / 100 / 2;
                    _swapTokensForETH(balanceOf(address(this)) - liquidityAmount);
                    uint256 ethBalance = address(this).balance;
                    uint256 ethForMarketing = (ethBalance * marketingRatio / 100) + (ethBalance * lpRatio / 100 / 4);
                    uint256 ethForDev = (ethBalance * devRatio / 100) + (ethBalance * lpRatio / 100 / 4);
                    uint256 ethForLP = ethBalance * lpRatio / 100 / 2;
                    _addLiquidity(balanceOf(address(this)), ethForLP);
                    bool success = false;
                    (success,) = marketingWallet.call{value: ethForMarketing, gas: 30000}("");
                    (success,) = devWallet.call{value: ethForDev, gas: 30000}("");
                }
                balances[to] += amount - (amount * sellTax / 100);
                emit Transfer(from, to, amount - (amount * sellTax / 100));
            }
        }
    }

    function _swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.addLiquidityETH{value: ethAmount}(address(this), tokenAmount, 0, 0, deadWallet, block.timestamp);
    }
}
