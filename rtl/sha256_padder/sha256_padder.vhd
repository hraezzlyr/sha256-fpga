library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sha256_padder is
    port(
        -- System signals
        clk_i : in std_logic;
        rst_i : in std_logic;

        -- SHA256 Padder - SHA256 Feeder interface
        padder_data_valid_i : in std_logic;
        padder_data_len_iv : in std_logic_vector(63 downto 0);
        padder_data_iv : in std_logic_vector(511 downto 0);
        padder_rdy_o : out std_logic;

        -- SHA256 Padder - SHA256 Message Scheduler interface
        scheduler_rdy_i : in std_logic;
        scheduler_data_valid_o : out std_logic;
        scheduler_data_ov : out std_logic_vector(511 downto 0)
    );
end entity sha256_padder;

architecture rtl of sha256_padder is
    type t_states is (idle, wait_len_rdy, pad_data, feed_scheduler);

    type t_reg is record
        state : t_states;

        internal_rst : std_logic;

        padder_remain_into_block : std_logic;
        padder_penultimate : std_logic;
        padder_end : std_logic;
        padder_add_block : std_logic;
        padder_last : std_logic;
        padder_bit_idx : integer range -512 to 511;
        padder_data_len : std_logic_vector(63 downto 0);
        padder_data : std_logic_vector(511 downto 0);
        padder_cnt : signed(64 downto 0);
    end record t_reg;

    -- The maximum data length in bits that could be padded in a one block
    constant c_max_padding_data_len_bit : natural := 447;

    -- The maximum data length in bits, in a one block of a chunk
    constant c_one_data_block_len_bit : natural := 512;

    constant c_rst_reg_vector : t_reg :=
    (
        state => idle,

        internal_rst => '0',

        padder_remain_into_block => '0',
        padder_penultimate => '0',
        padder_last => '0',
        padder_end => '0',
        padder_add_block => '0',
        padder_bit_idx => 0,
        padder_data_len => (others => '-'),
        padder_data => (others => '-'),
        padder_cnt => (others => '-')
    );

    -- Register signals
    signal r, rin : t_reg;

    signal s_add_block : std_logic;
begin
    combinatorial : process(all)
        variable v : t_reg;
    begin
        -- Update combinatorial logic
        v := r;

        -- Checking whether the remaining message data and padding will fit into
        -- one or two blocks. These flags indicate how padding is applied:
        -- '1' & (others => '0') & r.padder_data_len.
        -- r.padder_last is set when the remaining data and padding require
        -- one block OR when processing the final block. r.padder_penultimate is
        -- set when the remaining data and padding require two blocks.
        -- This distinction is important because ‘1’ can appear in
        -- the penultimate or last block, while the original message length
        -- appears only at the end of the padding.
        -- last = 0, penultimate = 0 - in progress,
        -- last = 1, penultimate = 0 - padding fits within a single block,
        -- last = 0, penultimate = 1 - the first block of a two-block padding,
        -- last = 1, penultimate = 1 - the last block of a two-block padding.
        if (r.padder_cnt <= c_max_padding_data_len_bit) then
            v.padder_last := '1';
        elsif (r.padder_cnt < c_one_data_block_len_bit) then
            v.padder_penultimate := '1';
        -- The padder_remain_into_block signal is intended for blocking
        -- padder_rdy_o signal when the remaining message data fits into
        -- a single block (= 512 bit).
        elsif (r.padder_cnt = c_one_data_block_len_bit) then
            v.padder_remain_into_block := '1';
        end if;

        -- The 10 least significant bits of r.padder_cnt are used to determine
        -- the boundary between message data and padding within a 512-bit block.
        -- Since 512 = 2^9 and 10th bit encodes the sign bit,
        -- these bits represent the remaining length modulo
        -- 512. This index is only used when processing the final message data.
        -- (len < 512 bits).
        v.padder_bit_idx := to_integer(r.padder_cnt(9 downto 0));
        -- This is set, when there must be added one more block
        -- (last = 1, penultimate = 1)
        -- and r.padder_data must be filled with zeros.
        if (r.padder_add_block) then
            v.padder_bit_idx := 0;
        end if;

        -- FSM
        case (r.state) is
            when idle =>
                v.padder_remain_into_block := '0';
                v.padder_penultimate := '0';
                v.padder_last := '0';
                v.padder_end := '0';
                v.padder_add_block := '0';
                v.padder_data_len := padder_data_len_iv;
                v.padder_cnt := signed('0' & padder_data_len_iv);
                if (padder_data_valid_i) then
                    v.state := wait_len_rdy;
                end if;

            -- Dummy state to correctly register r.padder_last,
            -- r.padder_penultimate and r.padder_bit_idx
            when wait_len_rdy =>
                v.state := pad_data;
            
            when pad_data =>
                -- Setting padding below according to r.padder_bit_idx,
                -- v.padder_last and v.padder_penultimate
                v.padder_data := padder_data_iv;
                if (r.padder_last) or (r.padder_penultimate) then
                    for x in 511 - r.padder_bit_idx downto 0 loop
                        v.padder_data(x) := '0';
                    end loop;
                    -- This XOR ensures that the initial padding '1' bit is
                    -- inserted exactly once. If padding spans two blocks,
                    -- the bit is inserted in the penultimate block and omitted
                    -- from the last one. Otherwise, it is inserted in
                    -- the last block.
                    v.padder_data(511 - r.padder_bit_idx) := (
                        r.padder_last xor r.padder_penultimate
                    );
                end if;
                if (r.padder_last) then
                    v.padder_data(63 downto 0) := r.padder_data_len;
                end if;

                v.padder_end := r.padder_last;

                if (padder_data_valid_i) then
                    v.padder_cnt := r.padder_cnt - c_one_data_block_len_bit;
                    v.state := feed_scheduler;

                    -- This signal is intended for blocking padder_rdy_o signal
                    -- when there is a need to set an additional data block.
                    -- It is when:
                    --  - penultimate = 1 - the first block of a two-block
                    --    padding
                    -- OR
                    --  - padder_remain_into_block = 1 - the remaining message
                    --    data fits into a single block (= 512 bit)
                    if (
                        (r.padder_penultimate) or
                        (r.padder_remain_into_block)
                    ) then
                        v.padder_add_block := '1';
                    end if;
                end if;

            when feed_scheduler =>
                if (scheduler_rdy_i) then
                    if (r.padder_end) then
                        v.state := idle;
                    else
                        v.state := pad_data;
                    end if;
                end if;

            when others =>
                v.internal_rst := '1';
        end case;

        if (rst_i) or (r.internal_rst) then
            v := c_rst_reg_vector;
        end if;

        -- Drive outputs 
        s_add_block <= r.padder_last;
        padder_rdy_o <= '1' when (
            r.state = pad_data and
            r.padder_add_block = '0'
        ) else '0';
        scheduler_data_valid_o <= '1' when (r.state = feed_scheduler) else '0';
        scheduler_data_ov <= r.padder_data;

        -- Update registers
        rin <= v;
    end process combinatorial;
    
    synchronous : process(clk_i)
    begin
        if rising_edge(clk_i) then
            r <= rin;
        end if;
    end process synchronous;
end architecture;