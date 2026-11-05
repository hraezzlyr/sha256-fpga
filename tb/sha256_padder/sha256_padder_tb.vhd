library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library osvvm;
use osvvm.randompkg.all;

use work.sha256_padder_pkg_tb.all;

entity sha256_padder_tb is
    generic(
        runner_cfg : string
    );
end sha256_padder_tb;

architecture tb of sha256_padder_tb is
    -- Frequency of the system clock (s_clk_100mhz)
    constant c_clk_100mhz_period : time := 10 ns;

    -- The maximum data length in bits, in a one block of a chunk.
    constant c_block_bit_len : natural := 512;

    -- The maximum data length in bits that could be padded in a one block.
    constant c_max_padded_data_len_bit : natural := 447;

    -- The minimum padding length that could be set in a one block.
    constant c_min_padding_len_bit : natural := (
        c_block_bit_len - c_max_padded_data_len_bit
    );
    
    -- System signals
    signal s_clk_100mhz : std_logic := '0';
    signal s_rst : std_logic := '1';

    -- SHA256 Padder input interface
    signal s_padder_rdy : std_logic;
    signal s_padder_din_valid : std_logic;
    signal s_padder_din_len : std_logic_vector(63 downto 0);
    signal s_padder_din : std_logic_vector(511 downto 0);
    
    -- SHA256 Padder - SHA256 Message Scheduler interface
    signal s_scheduler_rdy : std_logic;
    signal s_scheduler_dout_valid : std_logic;
    signal s_schedluer_dout : std_logic_vector(511 downto 0);

    -- Process synchronizer signal. It informs the main process that
    -- the feeder and/or receiver process have ended its work.
    signal s_process_synchronizer : std_logic_vector(1 downto 0) := "00";

    -- Flags intended for a control of hot one/zero tests.
    -- The s_hot_active flag indicates a hot one/zero test.
    -- The s_hot_move_ror flag indicates when to shift a hot one/zero.
    -- Whether or not a shift occurs is determined by a random draw.
    signal s_hot_active : std_logic := '0';
    signal s_hot_move_ror : std_logic := '0';

    -- Feeding data for testing input
    constant c_512_bit_blocks_nr : natural := 17;
    signal s_in_data : std_logic_vector(
        c_block_bit_len * c_512_bit_blocks_nr - 1 downto 0
    );

    -- Maximum value of input data length.
    -- Since an input vector is 512 * n length
    -- (where n is a number of 512-bit blocks), it must contain padding data.
    -- In this case, it would be the minimum length od padding data = 65 bits.
    -- This allows to accommodate output data in n blocks.
    -- Each testcase tests input data from 0 to c_testing_length bit length.
    constant c_max_testing_length : natural := (
        s_in_data'length - c_min_padding_len_bit
    );

    -- Signals to determine wait cycles for input data valid and
    -- output data ready signals. They allows to test handshake handling.
    signal s_padder_valid_wait_states : natural := 0;
    signal s_scheduler_rdy_wait_states : natural := 0;
begin
    -- Clock generation process
    p_gen_clock : process
    begin
        wait for (c_clk_100mhz_period / 2);
        s_clk_100mhz <= not s_clk_100mhz;
    end process p_gen_clock;

    -- DUT
    dut_entity : entity work.sha256_padder
        port map(
            clk_i => s_clk_100mhz,
            rst_i => s_rst,

            padder_data_valid_i => s_padder_din_valid,
            padder_data_len_iv => s_padder_din_len,
            padder_data_iv => s_padder_din,
            padder_rdy_o => s_padder_rdy,

            scheduler_rdy_i => s_scheduler_rdy,
            scheduler_data_valid_o => s_scheduler_dout_valid,
            scheduler_data_ov => s_schedluer_dout
        );

    -- The feeder process.
    p_feed_input : process
        variable v_blocks_nr : natural := 0;
    begin
        wait until (s_rst = '0');
        set_inputs : for x in 0 to c_max_testing_length loop
            move_input : for y in 0 to v_blocks_nr loop
                set_padder_din(
                    s_in_data(
                        s_in_data'left - c_block_bit_len * y downto 
                        s_in_data'left - c_block_bit_len * (1 + y) + 1
                    ),
                    std_logic_vector(to_unsigned((x), 64)),
                    s_padder_valid_wait_states,
                    s_clk_100mhz,
                    s_padder_rdy,
                    s_padder_din_valid,
                    s_padder_din,
                    s_padder_din_len
                );
            end loop move_input;
            
            -- Since a one block of data is 512-bit length, increment
            -- the counter including data about how
            -- For tested length = 0 skip incrementing, since the v_blocks_nr
            -- is already initiated.
            if (x mod c_block_bit_len = 0) and (x /= 0) then
                v_blocks_nr := v_blocks_nr + 1;
            end if;

            -- The s_hot_active flag indicates the moment when
            -- input data shifting should happen in the main process.
            -- It is intended for tests of a hot one/zero flow
            -- (s_hot_active = '1').
            if (s_hot_active) then
                s_hot_move_ror <= '1';
                wait for 1 ns;
                s_hot_move_ror <= '0';
            end if;
        end loop set_inputs;
        
        s_process_synchronizer(0) <= '1';
    end process p_feed_input;

    p_read_output : process
        variable v_expect_out : std_logic_vector(s_in_data'range);
        variable v_expect : std_logic_vector(c_block_bit_len - 1 downto 0);
        variable v_blocks_nr : natural := 0;
    begin
        wait until (s_rst = '0');
        check_outputs : for x in 0 to c_max_testing_length loop
             v_expect_out(
                v_expect_out'left downto
                v_expect_out'left + 1 - c_block_bit_len * (1 + v_blocks_nr)
            ) := get_expected_padder_dout(s_in_data, x);

            move_output : for y in 0 to v_blocks_nr loop
                v_expect := v_expect_out(
                    v_expect_out'left - c_block_bit_len * y downto
                    v_expect_out'left - c_block_bit_len * (1 + y) + 1
                );

                wait_padder_dout_rdy(
                    s_scheduler_rdy_wait_states,
                    s_clk_100mhz,
                    s_scheduler_rdy,
                    s_scheduler_dout_valid
                );
                    
                check(
                    s_schedluer_dout = v_expect,
                    "Incorrect padder output, len: " &
                        integer'image(x) &
                        ", get 0x" &
                        to_hstring(s_schedluer_dout) &
                        ", expected 0x" &
                        to_hstring(v_expect) &
                        "!!!"
                );
            end loop move_output;

            if (x mod c_block_bit_len = c_max_padded_data_len_bit) then
                v_blocks_nr := v_blocks_nr + 1;
            end if;
        end loop check_outputs;

        s_process_synchronizer(1) <= '1';
    end process p_read_output;

    -- Main VUnit test process. It initiates and control input data.
    -- Also, according to the s_process_synchronizer signal, it ends (or not)
    -- when a testcase ends.
    p_main: process
        variable v_rand : RandomPType;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            if run("counter_flow") then
                s_in_data <= init_with_16bit_counter(s_in_data'length);
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                wait until (and s_process_synchronizer);
            elsif run("only_zeros_flow") then
                s_in_data <= (others => '0');
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                wait until (and s_process_synchronizer);
            elsif run("only_ones_flow") then
                s_in_data <= (others => '1');
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                wait until (and s_process_synchronizer);
            elsif run("hot_one_flow") then
                s_hot_active <= '1';
                s_in_data <= init_with_hot_one(s_in_data'length);
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                while (s_process_synchronizer(0) = '0') loop
                    wait until (s_hot_move_ror = '1' or 
                        s_process_synchronizer(0) = '1'
                    );

                    if (v_rand.RandInt(0, 1) = 1) then
                        s_in_data <= s_in_data ror 1;
                    end if;
                    wait until (s_hot_move_ror = '0');
                end loop;
                wait until (s_process_synchronizer(1) = '1');
            elsif run("hot_zero_flow") then
                s_hot_active <= '1';
                s_in_data <= init_with_hot_zero(s_in_data'length);
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                while (s_process_synchronizer(0) = '0') loop
                    wait until (
                        s_hot_move_ror = '1' or
                        s_process_synchronizer(0) = '1'
                    );

                    if (v_rand.RandInt(0, 1) = 1) then
                        s_in_data <= s_in_data ror 1;
                    end if;
                    wait until (s_hot_move_ror = '0');
                end loop;
                wait until (s_process_synchronizer(1) = '1');
            elsif run("random_flow") then
                s_in_data <= init_with_8bit_random(s_in_data'length);
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                wait until (and s_process_synchronizer);
            elsif run("padder_valid_random_waits") then
                s_in_data <= init_with_8bit_random(s_in_data'length);
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                while (nand s_process_synchronizer)loop
                    s_padder_valid_wait_states <= v_rand.RandInt(0, 20);
                    wait until (rising_edge(s_clk_100mhz));
                end loop;
            elsif run("scheduler_rdy_random_waits") then
                s_in_data <= init_with_8bit_random(s_in_data'length);
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                while (nand s_process_synchronizer) loop
                    s_scheduler_rdy_wait_states <= v_rand.RandInt(0, 20);
                    wait until (rising_edge(s_clk_100mhz));
                end loop;
            elsif run("padder_valid_scheduler_rdy_random_waits") then
                s_in_data <= init_with_8bit_random(s_in_data'length);
                wait until (rising_edge(s_clk_100mhz));
                s_rst <= '0';
                while (nand s_process_synchronizer) loop
                    s_padder_valid_wait_states <= v_rand.RandInt(0, 20);
                    s_scheduler_rdy_wait_states <= v_rand.RandInt(0, 20);
                    wait until (rising_edge(s_clk_100mhz));
                end loop;
            end if;

        end loop;

        test_runner_cleanup(runner);
        wait;
    end process p_main;

    -- VUnit watchdog process
    p_watchdog : process
    begin
        test_runner_watchdog(runner, 15 ms);
        wait;
    end process;

end architecture;