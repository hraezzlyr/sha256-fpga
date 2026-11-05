library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sha256_scheduler is
    port(
        -- SYstem signals
        clk_i : in std_logic;
        rst_i : in std_logic;

        -- SHA256 Padder - SH256 Scheduler interface
        scheduler_data_valid_i : in std_logic;
        scheduler_data_iv : in std_logic_vector(511 downto 0);
        scheduler_rdy_o : out std_logic;

        -- SH256 Scheduler - SH256 Compression core interface
        compression_data_rdy_i : in std_logic;
        compression_data_ov : out std_logic_vector(31 downto 0);
        compression_data_valid_o : out std_logic
    );
end entity sha256_scheduler;

architecture rtl of sha256_scheduler is
    type t_reg is record
        word_idx : unsigned(3 downto 0);
        block_idx : unsigned(1 downto 0);

        scheduler_latched_din : std_logic;
        scheduler_data : unsigned(511 downto 0);
    end record t_reg;

    constant c_rst_reg_vector : t_reg :=
    (
        word_idx => (others => '0'),
        block_idx => (others => '0'),

        scheduler_latched_din => '0',
        scheduler_data => (others => '-')
    );

    signal r, rin : t_reg;
begin
    p_combinatorial : process(all)
        variable v : t_reg;
        variable v_ror3, v_ror7, v_ror18, v_s0 : unsigned(31 downto 0);
        variable v_ror10, v_ror17, v_ror19, v_s1 : unsigned(31 downto 0);
        variable v_s0_s1_sum, v_w_sum : unsigned(31 downto 0);
        variable v_sum : unsigned(31 downto 0);
    begin
        v := r;

        v_ror3 := r.scheduler_data(447 downto 416) ror 3;
        v_ror7 := r.scheduler_data(447 downto 416) ror 7;
        v_ror18 := r.scheduler_data(447 downto 416) ror 18;
        v_s0 := v_ror7 xor v_ror17 xor v_ror3;

        v_ror10 := r.scheduler_data(63 downto 32) ror 10;
        v_ror17 := r.scheduler_data(63 downto 32) ror 17;
        v_ror19 := r.scheduler_data(63 downto 32) ror 19;
        v_s1 := v_ror17 xor v_ror19 xor v_ror10;

        v_s0_s1_sum := v_s0 + v_s1;
        v_w_sum := (
            r.scheduler_data(511 downto 480) +
            r.scheduler_data(223 downto 192)
        );
        v_sum := v_s0_s1_sum + v_w_sum;

        if (scheduler_data_valid_i) and (r.scheduler_latched_din) then
            v.scheduler_latched_din := '1';
            v.scheduler_data := unsigned(scheduler_data_iv);
        end if;

        if (r.scheduler_latched_din) then
            v.word_idx := r.word_idx + 1;
            v.scheduler_data := r.scheduler_data(479 downto 0) & v_sum;

            if (r.word_idx = 0) and (compression_data_rdy_i = '0') then
                v.word_idx := (others => '0');
                v.scheduler_data := r.scheduler_data;
            end if;

            if (r.word_idx = 2 ** r.word_idx'length - 1) then
                v.block_idx := r.block_idx + 1;
                if (r.block_idx = 2 ** r.block_idx'length - 1) then
                    v.scheduler_latched_din := '0';
                end if;
            end if;
        end if;

        -- Check reset
        if (rst_i) then
            v := c_rst_reg_vector;
        end if;

        -- Drive outputs
        scheduler_rdy_o <= not r.scheduler_latched_din;

        compression_data_valid_o <= '1' when (
            r.word_idx = 0 and
            r.scheduler_latched_din = '1'
        ) else '0';
        compression_data_ov <= std_logic_vector(r.scheduler_data);

        rin <= v;
    end process p_combinatorial;

    p_synchronous : process(clk_i)
    begin
        if rising_edge(clk_i) then
            r <= rin;
        end if;
    end process p_synchronous;
end architecture rtl;