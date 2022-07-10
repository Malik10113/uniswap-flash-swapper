pragma solidity 0.5.17;

import "./UniswapV2Interfaces.sol";


contract UniswapFlashSwapper {

    enum SwapType {SimpleLoan, SimpleSwap, TriangularSwap}

    // CONSTANTS
    IUniswapV2Factory constant uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f); // same for all networks
    address constant ETH = address(0);

    // ACCESS CONTROL
    // Only the `permissionedPairAddress` may call the `uniswapV2Call` function
    address permissionedPairAddress = address(1);

    // DEFAULT TOKENS
    address WETH;
    address DAI;

    constructor(address _DAI, address _WETH) public {
        WETH = _WETH;
        DAI = _DAI;
    }

    // Fallback must be payable
    function() external payable {}

    // @notice Flash-borrows _amount of _tokenBorrow from a Uniswap V2 pair and repays using _tokenPay
    // @param _tokenBorrow The address of the token you want to flash-borrow, use 0x0 for ETH
    // @param _amount The amount of _tokenBorrow you will borrow
    // @param _tokenPay The address of the token you want to use to payback the flash-borrow, use 0x0 for ETH
    // @param _userData Data that will be passed to the `execute` function for the user
    // @dev Depending on your use case, you may want to add access controls to this function

    // @dev This initiates the flash borrow. See `simpleFlashSwapExecute` for the code that executes after the borrow.
    function simpleFlashSwap(
        address _tokenBorrow,
        uint _amount,
        address _tokenPay,
        bytes memory _userData
    ) private {
        permissionedPairAddress = uniswapV2Factory.getPair(_tokenBorrow, _tokenPay); // is it cheaper to compute this locally?
        address pairAddress = permissionedPairAddress; // gas efficiency
        require(pairAddress != address(0), "Requested pair is not available.");
        address token0 = IUniswapV2Pair(pairAddress).token0();
        address token1 = IUniswapV2Pair(pairAddress).token1();
        uint amount0Out = _tokenBorrow == token0 ? _amount : 0;
        uint amount1Out = _tokenBorrow == token1 ? _amount : 0;
        bytes memory data = abi.encode(
            SwapType.SimpleSwap,
            _tokenBorrow,
            _amount,
            _tokenPay,
            bytes(""),
            _userData
        );
        IUniswapV2Pair(pairAddress).swap(amount0Out, amount1Out, address(this), data);
    }

    // @notice This is the code that is executed after `simpleFlashSwap` initiated the flash-borrow
    // @dev When this code executes, this contract will hold the flash-borrowed _amount of _tokenBorrow
    function simpleFlashSwapExecute(
        address _tokenBorrow,
        uint _amount,
        address _tokenPay,
        address _pairAddress,
        bytes memory _userData
    ) 
    private{
        // compute the amount of _tokenPay that needs to be repaid
        address pairAddress = permissionedPairAddress; // gas efficiency
        uint pairBalanceTokenBorrow = IERC20(_tokenBorrow).balanceOf(pairAddress);
        uint pairBalanceTokenPay = IERC20(_tokenPay).balanceOf(pairAddress);
        uint amountToRepay = ((1000 * pairBalanceTokenPay * _amount) / (997 * pairBalanceTokenBorrow)) + 1;

        // get the orignal tokens the user requested
        address tokenBorrowed = _tokenBorrow;
        address tokenToRepay = _tokenPay;

        // do whatever the user wants
        execute(tokenBorrowed, _amount, tokenToRepay, amountToRepay, _userData);
       
        IERC20(_tokenPay).transfer(_pairAddress, amountToRepay);
    }
     // @notice Function is called by the Uniswap V2 pair's `swap` function
     function uniswapV2Call(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external {
        // access control
        require(msg.sender == permissionedPairAddress, "only permissioned UniswapV2 pair can call");
        require(_sender == address(this), "only this contract may initiate");

        // decode data
        (
            SwapType _swapType,
            address _tokenBorrow,
            uint _amount,
            address _tokenPay,
            bytes memory _triangleData,
            bytes memory _userData
        ) = abi.decode(_data, (SwapType, address, uint, address, bool, bool, bytes, bytes));
        simpleFlashSwapExecute(_tokenBorrow, _amount, _tokenPay, msg.sender, _userData);
        return;
        // NOOP to silence compiler "unused parameter" warning
        if (false) {
            _amount0;
            _amount1;
        }
    }

   
