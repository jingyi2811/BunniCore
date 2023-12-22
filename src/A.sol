pragma solidity 0.8.15;

import {BunniToken} from "./BunniToken.sol";
import {BunniLens} from "./BunniLens.sol";
import {Deviation} from "./Deviation.sol";
import {BunniHelper} from "./BunniHelper.sol";
import {BunniKey} from "src/interfaces/Structs.sol";
import {IBunniHub} from "src/interfaces/IBunniHub.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV3OracleHelper} from "./Oracle.sol";
import {FullMath} from "./lib/FullMath.sol";

contract MyPool {
    using FullMath for uint256;

    struct BunniParams {
        address bunniLens;
        uint16 twapMaxDeviationsBps;
        uint32 twapObservationWindow;
    }

    constructor() public {
    }

    error BunniPrice_Params_InvalidBunniToken(address bunniToken_);
    error BunniPrice_Params_InvalidBunniLens(address bunniLens_);
    error BunniPrice_Params_HubMismatch(address bunniTokenHub_, address bunniLensHub_);

    error BunniPrice_PriceMismatch(
        address pool_,
        uint256 baseInQuoteTWAP_,
        uint256 baseInQuotePrice_
    );

    uint16 internal constant TWAP_MAX_DEVIATION_BASE = 10_000; // 100%

    function getBunniTokenPrice(
        address bunniToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode the parameters
        BunniParams memory params;
        {
            params = abi.decode(params_, (BunniParams));
            if (params.bunniLens == address(0)) {
                revert BunniPrice_Params_InvalidBunniLens(params.bunniLens);
            }

            // Check for invalid bunniToken_
            if (bunniToken_ == address(0)) {
                revert BunniPrice_Params_InvalidBunniToken(bunniToken_);
            }
        }

        // Validate the token
        BunniToken token = BunniToken(bunniToken_);
        BunniLens lens = BunniLens(params.bunniLens);
        {
            address tokenHub;
            try token.hub() returns (IBunniHub tokenHub_) {
                tokenHub = address(tokenHub_);
            } catch (bytes memory) {
                revert BunniPrice_Params_InvalidBunniToken(bunniToken_);
            }

            // Validate the lens
            address lensHub;
            try lens.hub() returns (IBunniHub lensHub_) {
                lensHub = address(lensHub_);
            } catch (bytes memory) {
                revert BunniPrice_Params_InvalidBunniLens(params.bunniLens);
            }

            // Check that the hub matches
            if (tokenHub != lensHub) {
                revert BunniPrice_Params_HubMismatch(tokenHub, lensHub);
            }
        }

        // Validate reserves
        _validateReserves(
            _getBunniKey(token),
            lens,
            params.twapMaxDeviationsBps,
            params.twapObservationWindow
        );

        // Fetch the reserves
        uint256 totalValue = _getTotalValue(token, lens, outputDecimals_);

        return totalValue;
    }

    function _getTotalValue(
        BunniToken token_,
        BunniLens lens_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        (address token0, uint256 reserve0, address token1, uint256 reserve1) = _getBunniReserves(
            token_,
            lens_,
            outputDecimals_
        );
        uint256 outputScale = 10 ** outputDecimals_;

        // Determine the value of each reserve token in USD
        uint256 totalValue;
//        totalValue += _PRICE().getPrice(token0).mulDiv(reserve0, outputScale);
//        totalValue += _PRICE().getPrice(token1).mulDiv(reserve1, outputScale);

        totalValue = 1;

        return totalValue;
    }

    function _getBunniReserves(
        BunniToken token_,
        BunniLens lens_,
        uint8 outputDecimals_
    ) internal view returns (address token0, uint256 reserve0, address token1, uint256 reserve1) {
        BunniKey memory key = _getBunniKey(token_);
        (uint112 reserve0_, uint112 reserve1_) = lens_.getReserves(key);

        // Get the token addresses
        token0 = key.pool.token0();
        token1 = key.pool.token1();
        uint8 token0Decimals = ERC20(token0).decimals();
        uint8 token1Decimals = ERC20(token1).decimals();
        reserve0 = uint256(reserve0_).mulDiv(10 ** outputDecimals_, 10 ** token0Decimals);
        reserve1 = uint256(reserve1_).mulDiv(10 ** outputDecimals_, 10 ** token1Decimals);
    }

    function _getBunniKey(BunniToken token_) internal view returns (BunniKey memory) {
        return
        BunniKey({
        pool: token_.pool(),
        tickLower: token_.tickLower(),
        tickUpper: token_.tickUpper()
        });
    }

    function _validateReserves(
        BunniKey memory key_,
        BunniLens lens_,
        uint16 twapMaxDeviationBps_,
        uint32 twapObservationWindow_
    ) internal view {
        uint256 reservesTokenRatio = BunniHelper.getReservesRatio(key_, lens_);
        uint256 twapTokenRatio = UniswapV3OracleHelper.getTWAPRatio(
            address(key_.pool),
            twapObservationWindow_
        );

        // Revert if the relative deviation is greater than the maximum.
        if (
        // `isDeviatingWithBpsCheck()` will revert if `deviationBps` is invalid.
            Deviation.isDeviatingWithBpsCheck(
                reservesTokenRatio,
                twapTokenRatio,
                twapMaxDeviationBps_,
                TWAP_MAX_DEVIATION_BASE
            )
        ) {
            revert BunniPrice_PriceMismatch(address(key_.pool), twapTokenRatio, reservesTokenRatio);
        }
    }
}
