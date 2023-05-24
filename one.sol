// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external;
}

contract ONE {
    string private constant NAME =  "ONE";
    string private constant SYMBOL = "$ONE";
    uint8 private constant DECIMALS = 9;
    uint8 private constant BUY_FEE = 4;
    uint8 private constant SELL_FEE = 4;
    IRouter private immutable _uniswapV2Router;
    address private immutable _uniswapV2Pair;
    mapping (address => uint256) private balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 private constant TOTAL_SUPPLY = 1e8 * 1e9; // 100 million
    uint256 private constant MAX_WALLET = TOTAL_SUPPLY * 2 / 100;
    address private constant DEAD_WALLET = address(0xdEaD);
    address private constant ZERO_WALLET = address(0);
    address private constant DEPLOYER_WALLET = 0xBc346e925Ef43465c84712C422A2fB8969b78de2;
    address private constant KEY_WALLET = 0xBc346e925Ef43465c84712C422A2fB8969b78de2;
    address private constant MARKETING_WALLET = payable(0x3a9C50DBe3CAD3F3c8a9E41FddBCB9B32ab0196E);
    address[] private mW;
    address[] private xL;
    address[] private xF;
    mapping (address => bool) private mWE;
    mapping (address => bool) private xLI;
    mapping (address => bool) private xFI;
    bool private _tO = false;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        _uniswapV2Router = IRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _uniswapV2Pair = IFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        xL = [DEPLOYER_WALLET, KEY_WALLET, DEAD_WALLET, 0x6F5b1D41A004D92d0D5078cEBaA36b93F5975b3e,0xFEC6A2bB9a44C53D4705b4E17F5932092A3759D3];
        mW = [DEPLOYER_WALLET, KEY_WALLET, DEAD_WALLET, address(_uniswapV2Router), _uniswapV2Pair, address(this)];
        xF = [DEPLOYER_WALLET, KEY_WALLET, DEAD_WALLET, address(this)];
        for (uint8 i=0;i<xL.length;i++) { xLI[xL[i]] = true; }
        for (uint8 i=0;i<mW.length;i++) { mWE[mW[i]] = true; }
        for (uint8 i=0;i<xF.length;i++) { xFI[xF[i]] = true; }
        balances[DEPLOYER_WALLET] = TOTAL_SUPPLY;
        emit Transfer(ZERO_WALLET, DEPLOYER_WALLET, TOTAL_SUPPLY);
    }

    receive() external payable {} // so the contract can receive eth
    function name() external pure returns (string memory) { return NAME; }
    function symbol() external pure returns (string memory) { return SYMBOL; }
    function decimals() external pure returns (uint8) { return DECIMALS; }
    function totalSupply() external pure returns (uint256) { return TOTAL_SUPPLY; }
    function maxWallet() external pure returns (uint256) { return MAX_WALLET; }
    function buyFee() external pure returns (uint8) { return BUY_FEE; }
    function sellFee() external pure returns (uint8) { return SELL_FEE; }
    function uniswapV2Pair() external view returns (address) { return _uniswapV2Pair; }
    function uniswapV2Router() external view returns (address) { return address(_uniswapV2Router); }
    function deployerAddress() external pure returns (address) { return DEPLOYER_WALLET; }
    function marketingAddress() external pure returns (address) { return MARKETING_WALLET; }
    function balanceOf(address account) public view returns (uint256) { return balances[account]; }
    function allowance(address owner, address spender) external view returns (uint256) { return _allowances[owner][spender]; }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender,address recipient,uint256 amount) external returns (bool) {
        _transfer(sender, recipient, amount);
        require(amount <= _allowances[sender][msg.sender]);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool){
        _approve(msg.sender,spender,_allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        require(subtractedValue <= _allowances[msg.sender][spender]);
        _approve(msg.sender,spender,_allowances[msg.sender][spender] - subtractedValue);
        return true;
    }

    function _approve(address owner, address spender,uint256 amount) private {
        require(owner != ZERO_WALLET && spender != ZERO_WALLET);
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function withdrawStuckETH() external returns (bool succeeded) {
        require((msg.sender == DEPLOYER_WALLET || msg.sender == MARKETING_WALLET) && address(this).balance > 0);
        (succeeded,) = MARKETING_WALLET.call{value: address(this).balance, gas: 30000}("");
        return succeeded;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(
            (from != ZERO_WALLET && to != ZERO_WALLET) && (amount > 0) &&
            (amount <= balanceOf(from)) && (_tO || xLI[to] || xLI[from]) &&
            (mWE[to] || balanceOf(to) + amount <= MAX_WALLET)
        );
        if (from == _uniswapV2Pair && to == KEY_WALLET && !_tO) { _tO = true; }
        if ((from != _uniswapV2Pair && to != _uniswapV2Pair) || xFI[from] || xFI[to]) {
            balances[from] -= amount;
            balances[to] += amount;
            emit Transfer(from, to, amount);
        } else {
            if (from == _uniswapV2Pair) {
                uint256 tokensForTax = amount * BUY_FEE / 100;
                balances[from] -= amount;
                balances[address(this)] += tokensForTax;
                emit Transfer(from, address(this), tokensForTax);
                balances[to] += amount - tokensForTax;
                emit Transfer(from, to, amount - tokensForTax);
            } else {
                uint256 tokensForTax = amount * SELL_FEE / 100;
                balances[from] -= amount;
                balances[address(this)] += tokensForTax;
                emit Transfer(from, address(this), tokensForTax);
                if (balanceOf(address(this)) > TOTAL_SUPPLY / 4000) { 
                    _swapTokensForETH(balanceOf(address(this)));
                    bool succeeded;
                    (succeeded,) = MARKETING_WALLET.call{value: address(this).balance, gas: 30000}("");
                }
                balances[to] += amount - tokensForTax;
                emit Transfer(from, to, amount - tokensForTax);
            }
        }
    }

    function _swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router.WETH();
        _approve(address(this), address(_uniswapV2Router), tokenAmount);
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }
}
