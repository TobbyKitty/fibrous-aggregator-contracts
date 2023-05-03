#[contract]
mod newRouter {
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::ContractAddress;
    use starknet::contract_address_try_from_felt252;
    use starknet::ContractAddressZeroable;
    use zeroable::Zeroable;
    use array::ArrayTrait;
    use fibrous::structs::SwapDesc;
    use fibrous::structs::SwapPath;
    use fibrous::interfaces::IERC20Dispatcher;
    use fibrous::interfaces::IERC20DispatcherTrait;
    use fibrous::ownable::Ownable;
    use gas::withdraw_gas;
    use gas::withdraw_gas_all;
    use array::array_new;
    use array::array_append;
    use option::OptionTrait;

    #[abi]
    trait Amm {
        fn swap(token_from: ContractAddress, amount_from: u256) -> u256;
    }

    struct Storage {
        _swap_handler: ContractAddress,
        swap_addresses: LegacyMap<felt252, ContractAddress>,
    }

    #[constructor]
    fn constructor(owner: ContractAddress) {
        Ownable::initializer(owner);
    }

    // @notice Set swap address
    // @param idx index of swap address in swap_addresses array
    // @param _swap_address address array
    // @dev only owner can call
    #[external]
    fn set_swap_address(idx: felt252, _swap_address: ContractAddress) {
        Ownable::assert_only_owner();
        swap_addresses::write(idx, _swap_address)
    }

    // @notice Swap tokens from one to another using fibrous router api
    // @param desc Swap Description struct
    // @param path Swap path struct
    #[external]
    fn swap(desc: SwapDesc, mut path: SwapPath) {
        let swap_handler = _swap_handler::read();
        let caller = get_caller_address();
        let this_address = get_contract_address();

        IERC20Dispatcher {
            contract_address: desc.token_in
        }.transferFrom(caller, this_address, desc.amt);

        assert(!path.path_0.is_zero(), 'Source token can not be zero');
        assert(!path.path_3.is_zero(), 'Destination token cant be zero');

        _swap(desc.amt, path.path_0, ref path, 0);

        let after_balance = IERC20Dispatcher {
            contract_address: desc.token_out
        }.balanceOf(this_address);

        assert(after_balance >= desc.min_rcv, 'Min. receive amount not reached');

        IERC20Dispatcher { contract_address: desc.token_out }.transfer(caller, after_balance);
    }

    fn _swap(amt: u256, src_token: ContractAddress, ref path: SwapPath, step: felt252) {
        match withdraw_gas() {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut data = array_new::<felt252>();
                array_append::<felt252>(ref data, 'OOG');
                panic(data);
            },
        }
        let this_address = get_contract_address();
        let (next_to_token, next_pool, next_swap) = _get_next_swap(path, step);

        if (next_to_token.is_zero()) {
            return _swap(amt, src_token, ref path, step + 1);
        }
        let amt_out = _swap_amm(src_token, next_to_token, next_pool, amt);

        if (next_to_token != path.path_3) {
            return _swap(amt_out, next_to_token, ref path, step + 1);
        }
        return ();
    }

    fn _swap_amm(
        token_in: ContractAddress,
        token_out: ContractAddress,
        pool: ContractAddress,
        amount_in: u256
    ) -> u256 {
        match withdraw_gas() {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut data = array_new::<felt252>();
                array_append::<felt252>(ref data, 'OOG');
                panic(data);
            },
        }
        assert(!token_in.is_zero(), 'Token in cannot be zero');
        assert(!token_out.is_zero(), 'Token out cannot be zero');
        assert(!pool.is_zero(), 'Pool cannot be zero');
        assert(token_in != token_out, 'Same token provided');
        let this_address = get_contract_address();

        let amount_out = AmmDispatcher {
            contract_address: pool
        }.swap(
            token_in, amount_in
        ); // TODO: swap function need to be dynamic cuz all pools almost have different swap function and none of them return

        let out_balance = IERC20Dispatcher { contract_address: token_out }.balanceOf(this_address);
        assert(out_balance >= amount_out, 'Not enough balance');
        return amount_out;
    }

    fn _get_next_swap(path: SwapPath, idx: felt252) -> (ContractAddress, ContractAddress, felt252) {
        if idx == 0 {
            (path.path_0, path.pool_1, path.swap_1)
        } else if idx == 1 {
            (path.path_1, path.pool_2, path.swap_2)
        } else if idx == 2 {
            (path.path_2, path.pool_3, path.swap_3)
        } else {
            (ContractAddressZeroable::zero(), ContractAddressZeroable::zero(), 0)
        }
    }
}
