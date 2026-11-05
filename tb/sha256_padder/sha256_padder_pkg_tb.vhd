library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

library osvvm;
use osvvm.randompkg.all;

package sha256_padder_pkg_tb is
    function init_with_16bit_counter(
        vector_len : natural
    ) return std_logic_vector;
    
    function init_with_hot_one(
        vector_len : natural
    ) return std_logic_vector;

    function init_with_hot_zero(
        vector_len : natural
    ) return std_logic_vector;

    impure function init_with_8bit_random(
        vector_len : natural
    ) return std_logic_vector;

    function get_expected_padder_dout(
        din : std_logic_vector;
        vector_len : natural
    ) return std_logic_vector;

    procedure set_padder_din(
        constant din_value : std_logic_vector;
        constant din_value_len : std_logic_vector;
        constant valid_wait_states : natural;
        signal clk : in std_logic;
        signal padder_rdy : in std_logic;
        signal padder_valid : out std_logic;
        signal padder_din : out std_logic_vector;
        signal padder_din_len : out std_logic_vector
    );

    procedure wait_padder_dout_rdy(
        constant rdy_wait_states : natural;
        signal clk : in std_logic;
        signal scheduler_rdy : out std_logic;
        signal scheduler_dout_valid : in std_logic
    );
end package sha256_padder_pkg_tb;

package body sha256_padder_pkg_tb is
    function init_with_16bit_counter(
        vector_len : natural
    ) return std_logic_vector is
        constant word_len : natural := 16;
        variable dout : std_logic_vector(vector_len - 1 downto 0);
    begin
        assert (vector_len mod word_len = 0)
            report "ERROR: Data length must be a multiple of a word = 16 bits!"
            severity failure;
        
        for x in 0 to (vector_len / word_len) - 1 loop
            dout(
                vector_len - 1 - word_len * x downto
                vector_len - word_len * (1 + x)
            ) := (
                std_logic_vector(to_unsigned(x, word_len))
            );
        end loop;

        return dout;
    end function init_with_16bit_counter;

    function init_with_hot_one(
        vector_len : natural
    ) return std_logic_vector is
        variable dout : std_logic_vector(vector_len - 1 downto 0);
    begin
        dout(vector_len - 1) := '1';
        for x in vector_len - 2 downto 0 loop
            dout(x) := '0';
        end loop;

        return dout;
    end function init_with_hot_one;

    function init_with_hot_zero(
        vector_len : natural
    ) return std_logic_vector is
        variable dout : std_logic_vector(vector_len - 1 downto 0);
    begin
        dout(vector_len - 1) := '0';
        for x in vector_len - 2 downto 0 loop
            dout(x) := '1';
        end loop;

        return dout;
    end function init_with_hot_zero;

    impure function init_with_8bit_random(
        vector_len : natural
    ) return std_logic_vector is
        constant byte_len : natural := 8;
        variable v_random : RandomPType;
        variable dout : unsigned(vector_len - 1 downto 0);
    begin
        assert (vector_len mod 8 = 0)
            report "ERROR: Data length must be a multiple of a byte!"
            severity failure;
        for x in 0 to (vector_len / byte_len) - 1 loop
            dout(
                vector_len - 1 - byte_len * x downto
                vector_len - byte_len * (1 + x)
            ) := to_unsigned(v_random.RandInt(0, 255), byte_len);
        end loop;

        return std_logic_vector(dout);

    end function init_with_8bit_random;

    function get_expected_padder_dout(
        din : std_logic_vector;
        vector_len : natural
    ) return std_logic_vector is
        constant dout_size : natural := (
            512 * natural(ceil((real(vector_len) + 64.0 + 1.0) / 512.0))
        );
        variable dout : std_logic_vector(dout_size - 1 downto 0);
    begin
        assert (vector_len <= din'length)
            report "ERROR: Given vector length is higher than input size!"
            severity failure;
        assert (not din'ascending)
            report "ERROR: `din` vector must use downto direction!"
            severity failure; 

        if (vector_len > 0) then
            dout(dout_size - 1 downto dout_size - vector_len) := (
                din(din'left downto din'left - vector_len + 1)
            );
        end if;

        for y in dout_size - 1 - vector_len downto 0 loop
            dout(y) := '0'; 
        end loop;
        
        dout(dout_size - 1 - vector_len) := '1';
        dout(63 downto 0) := std_logic_vector(to_unsigned(vector_len, 64));

        return dout;
    end function get_expected_padder_dout;

    procedure set_padder_din(
        constant din_value : std_logic_vector;
        constant din_value_len : std_logic_vector;
        constant valid_wait_states : natural;
        signal clk : in std_logic;
        signal padder_rdy : in std_logic;
        signal padder_valid : out std_logic;
        signal padder_din : out std_logic_vector;
        signal padder_din_len : out std_logic_vector
    ) is
    begin
        for x in 1 to valid_wait_states loop
            wait until (rising_edge(clk));
        end loop;
        padder_valid <= '1';
        padder_din_len <= din_value_len;
        padder_din <= din_value;
        wait until (rising_edge(clk) and padder_rdy = '1');
        padder_valid <= '0';
    end procedure set_padder_din;

    procedure wait_padder_dout_rdy(
        constant rdy_wait_states : natural;
        signal clk : in std_logic;
        signal scheduler_rdy : out std_logic;
        signal scheduler_dout_valid : in std_logic
    ) is
    begin
        for x in 1 to rdy_wait_states loop
            wait until (rising_edge(clk));
        end loop;
        scheduler_rdy <= '1';
        wait until (rising_edge(clk) and (scheduler_dout_valid = '1'));
        scheduler_rdy <= '0';
    end procedure wait_padder_dout_rdy;
end package body sha256_padder_pkg_tb;