-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2024 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): xkubovv00 <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 	-- PC (programovy citac)
	signal PC : std_logic_vector(12 downto 0);	-- adresa do pameti ma 12 bitu
	signal PC_INC : std_logic;
	signal PC_DEC : std_logic;

	-- PTR (ukazatel do pameti dat)
	signal PTR : std_logic_vector(12 downto 0);
	signal PTR_INC : std_logic;
	signal PTR_DEC : std_logic;

	-- TMP (pomocna promenna)
	signal TMP : std_logic_vector(7 downto 0);
	signal TMP_LD : std_logic;

	-- MX1 (multiplexor pro vyber adresy v PC nebo PTR)
	signal MX1_SEL : std_logic;

	-- MX2 (multiplexor pro vyber prepsani dat v pameti)
	signal MX2_SEL : std_logic_vector(1 downto 0);

	-- CNT (pocitadlo pro vnorene cykly)
	signal CNT : std_logic_vector(7 downto 0);
	signal CNT_INC : std_logic;
	signal CNT_DEC : std_logic;

	-- FSM (radic)
	type t_state is (idle, init_r, init_cmp, fetch, decode,
		ptr_inc_ex, ptr_dec_ex,
		ptr_val_inc_r, ptr_val_inc_w,
		ptr_val_dec_r, ptr_val_dec_w,
		while_beg_r, while_beg_cmp, while_beg_jmp, while_beg_skip, while_beg_cnt,
		while_end_r, while_end_cmp, while_end_jmp, while_end_skip, while_end_cnt,
		ptr_val_to_tmp_r, ptr_val_to_tmp_w,
		tmp_to_ptr_val_r,
		putchar_ptr_val_r, putchar_ptr_val_out,
		getchar_req, getchar_w,
		nop, prog_end);
	signal pstate : t_state := idle;
	signal nstate : t_state;

begin 
	-- PC (programovy citac)
	reg_PC: process(CLK, RESET)
	begin
	    if (RESET = '1') then
			PC <= (others => '0');
	    elsif (rising_edge(CLK)) then
			if (PC_INC = '1') then
		    	PC <= PC + 1;
			elsif (PC_DEC = '1') then
		    	PC <= PC - 1;
			end if;
	    end if;
	end process;

	-- PTR (ukazatel do pameti dat)
	reg_PTR: process(CLK, RESET)
	begin
	    if (RESET = '1') then
			PTR <= (others => '0');
		elsif (rising_edge(CLK)) then
			if (PTR_INC = '1') then
		    	PTR <= PTR + 1;
			elsif (PTR_DEC = '1') then
		    	PTR <= PTR - 1;
			end if;
	    end if;
	end process;

	-- TMP (pomocna promenna)
	reg_TMP: process(CLK, RESET)
	begin
	    if (RESET = '1') then
			TMP <= (others => '0');
	    elsif (rising_edge(CLK)) then
			if (TMP_LD = '1') then
		    	TMP <= DATA_RDATA;
			end if;
	    end if;
	end process;

	-- MX1 (multiplexor pro vyber adresy v PC nebo PTR)
	mx1: process(PC, PTR, MX1_SEL)
	begin
	    case MX1_SEL is
			when '0' => DATA_ADDR <= PC;
			when '1' => DATA_ADDR <= PTR;
			when others => null;
	    end case;
	end process;

	-- MX2 (multiplexor pro vyber prepsani dat v pameti)
	mx2: process(IN_DATA, TMP, DATA_RDATA, MX2_SEL)
	begin
	    case MX2_SEL is
			when "00" => DATA_WDATA <= DATA_RDATA + 1;
			when "01" => DATA_WDATA <= DATA_RDATA - 1;
			when "10" => DATA_WDATA <= TMP;
			when "11" => DATA_WDATA <= IN_DATA;
			when others => null;
	    end case;
	end process;

	-- CNT (pocitadlo pro vnorene cykly)
	counter: process(CLK, RESET)
	begin
	    if (RESET = '1') then
			CNT <= (others => '0');
	    elsif (rising_edge(CLK)) then
			if (CNT_INC = '1') then
		    	CNT <= CNT + 1;
			elsif (CNT_DEC = '1') then
		    	CNT <= CNT - 1;
			end if;
	    end if;
	end process;

	-- FSM (radic)
	-- pstate registr
	FSM_pstate: process(CLK, RESET)
	begin
	    if (RESET = '1') then
			pstate <= idle;
	    elsif (rising_edge(CLK)) then
			pstate <= nstate;
	    end if;
	end process;

	-- nstate logic + output logic
	FSM_nstate: process (pstate, IN_VLD, OUT_BUSY, EN, DATA_RDATA, CNT)
	begin
	    IN_REQ <= '0';
	    OUT_WE <= '0';
	    OUT_DATA <= X"00";
	    READY <= '1';
	    DONE <= '0';
	    TMP_LD <= '0';
	    PTR_INC <= '0';
	    PTR_DEC <= '0';
	    PC_INC <= '0';
	    PC_DEC <= '0';
	    MX1_SEL <= '0';
	    MX2_SEL <= "11";
	    DATA_RDWR <= '0';
	    DATA_EN <= '0';
	    CNT_INC <= '0';
		OUT_INV <= '0';
	    CNT_DEC <= '0';

	    case pstate is
		-- pocatecni stav
		when idle =>
		 	READY <= '0';
		    if (EN = '1') then
				nstate <= init_r;
		    else
				nstate <= idle;
		    end if;

		-- inicializace ukazatele na data
		when init_r =>
			READY <= '0';
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    nstate <= init_cmp;
		when init_cmp =>
		    if (DATA_RDATA = x"40") then
				PTR_INC <= '1';
				READY <= '1';
				nstate <= fetch;
		    else
				PTR_INC <= '1';
				nstate <= init_r;
		    end if;

		-- fetch (ziskani nasledujici instrukce)
		when fetch =>
		    if (EN = '1') then
				DATA_EN <= '1';
				DATA_RDWR <= '1';		-- rezim cteni
				MX1_SEL <= '0';			-- hodnota na adrese PC
				nstate <= decode;
		    else
				nstate <= idle;
		    end if;

		-- decode
		when decode =>
		    case (DATA_RDATA) is
			when X"3E" => nstate <= ptr_inc_ex;			-- '>'
			when X"3C" => nstate <= ptr_dec_ex;			-- '<'
			when X"2B" => nstate <= ptr_val_inc_r;		-- '+'
			when X"2D" => nstate <= ptr_val_dec_r;		-- '-'
			when X"5B" => nstate <= while_beg_r;		-- '['
			when X"5D" => nstate <= while_end_r;		-- ']'
			when X"24" => nstate <= ptr_val_to_tmp_r;	-- '$'
			when X"21" => nstate <= tmp_to_ptr_val_r;	-- '!'
			when X"2E" => nstate <= putchar_ptr_val_r;	-- '.'
			when X"2C" => nstate <= getchar_req;		-- ','
			when X"40" => nstate <= prog_end;			-- '@'
			when others => nstate <= nop;
		    end case;

		-- nop (zadna instrukce) - preskakovani neznamych
		when nop =>
		    PC_INC <= '1';
		    nstate <= fetch;

		-- '>' (ptr += 1)
		when ptr_inc_ex =>
		    PTR_INC <= '1';
		    PC_INC <= '1';
		    nstate <= fetch;

		-- '<' (ptr -= 1;)
		when ptr_dec_ex =>
		    PTR_DEC <= '1';
		    PC_INC <= '1';
		    nstate <= fetch;

		-- '+' (*ptr += 1;)
		-- 1. faze - nacteni hodnoty
		when ptr_val_inc_r =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    PC_INC <= '1';
		    nstate <= ptr_val_inc_w;
		-- 2. faze - inkrementace
		when ptr_val_inc_w =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '0';		-- rezim zapisu
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    MX2_SEL <= "00";		-- inkrementace
		    nstate <= fetch;

		-- '-' (*ptr -= 1;)
		-- 1. faze - nacteni hodnoty
		when ptr_val_dec_r =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    PC_INC <= '1';
		    nstate <= ptr_val_dec_w;
		-- 2. faze - dekrementace
		when ptr_val_dec_w =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '0';		-- rezim zapisu
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    MX2_SEL <= "01";		-- dekrementace hodnoty v paměti
		    nstate <= fetch;

		-- '[' (while (*ptr) {)
		when while_beg_r =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    PC_INC <= '1';
		    nstate <= while_beg_cmp;
		-- podminka
		when while_beg_cmp =>
		    if (DATA_RDATA = X"00") then
				DATA_EN <= '1';
				DATA_RDWR <= '1';		-- rezim cteni
				CNT_INC <= '1';
				MX1_SEL <= '1';			-- hodnota na adrese PTR
				nstate <= while_beg_jmp;
		    else
				nstate <= fetch;
		    end if;
		-- nacteni nasledujici instrukce
		when while_beg_jmp =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';			-- rezim cteni
		    MX1_SEL <= '0';				-- hodnota na adrese PC
		    nstate <= while_beg_skip;
		-- preskoceni nasledujici instrukce, kdyz '[' nebo ']', tak zmena CNT
		when while_beg_skip =>
		    if (DATA_RDATA = X"5B") then		-- instrukce '['
				CNT_INC <= '1';
		    elsif (DATA_RDATA = X"5D") then		-- instrukce ']'
				CNT_DEC <= '1';
		    end if;
		    nstate <= while_beg_cnt;
		-- porovnani CNT
		when while_beg_cnt =>
		    PC_INC <= '1';
		    if (CNT = X"00") then
				nstate <= fetch;
		    else
				nstate <= while_beg_jmp;
		    end if;

		-- ']' (})
		when while_end_r =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    nstate <= while_end_cmp;
		-- podminka
		when while_end_cmp =>
		    -- konec cyklu
		    if (DATA_RDATA <= X"00") then
				PC_INC <= '1';
				nstate <= fetch;
		    -- pohyb zpatky
		    else
				CNT_INC <= '1';
				PC_DEC <= '1';
				nstate <= while_end_jmp;
		    end if;
		-- nacteni nasledujici instrukce
		when while_end_jmp =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '0';			-- hodnota na adrese PC
		    nstate <= while_end_skip;
		-- preskoceni nasledujici instrukce, kdyz '[' nebo ']', tak zmena CNT
		when while_end_skip =>
		    if (DATA_RDATA = X"5B") then	-- instrukce '['
				CNT_DEC <= '1';
		    elsif (DATA_RDATA = X"5D") then	-- instrukce ']'
				CNT_INC <= '1';
		    end if;
		    nstate <= while_end_cnt;
		-- porovnani CNT
		when while_end_cnt =>
		    if (CNT = X"00") then
				PC_INC <= '1';
				nstate <= fetch;
		    else
				PC_DEC <= '1';
				nstate <= while_end_jmp;
		    end if;

		-- '$' (tmp = *ptr;)
		-- 1. faze - nacteni hodnoty
		when ptr_val_to_tmp_r =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    PC_INC <= '1';
		    nstate <= ptr_val_to_tmp_w;
		-- 2. faze - ulozeni do tmp
		when ptr_val_to_tmp_w =>
		    TMP_LD <= '1';
		    nstate <= fetch;
	    
		-- '!' (*ptr = tmp;)
		when tmp_to_ptr_val_r =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '0';		-- rezim zapisu
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    MX2_SEL <= "10";		-- hodnota v TMP
		    PC_INC <= '1';
		    nstate <= fetch;

		-- '.' (putchar(*ptr);)
		-- 1. faze - nacteni hodnoty
		when putchar_ptr_val_r =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '1';		-- rezim cteni
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    PC_INC <= '1';
		    nstate <= putchar_ptr_val_out;
		-- 2. faze - vypis na vystup
		when putchar_ptr_val_out =>
		    if (OUT_BUSY = '0') then
				OUT_DATA <= DATA_RDATA;
				OUT_WE <= '1';
				nstate <= fetch;
		    else
				nstate <= putchar_ptr_val_out;
		    end if;

		-- ',' (*ptr = getchar();)
		when getchar_req =>
		    IN_REQ <= '1';
		    if (IN_VLD = '1') then
				nstate <= getchar_w;
		    else
				nstate <= getchar_req;
		    end if;
		when getchar_w =>
		    DATA_EN <= '1';
		    DATA_RDWR <= '0';		-- rezim zapisu
		    MX1_SEL <= '1';			-- hodnota na adrese PTR
		    MX2_SEL <= "11";		-- IN_DATA
		    PC_INC <= '1';
		    nstate <= fetch;

		-- '@' (return;) - ukončení programu
		when prog_end =>
			DONE <= '1';
		    nstate <= prog_end;

		when others =>
		    nstate <= idle;
	    end case;
	end process;
end behavioral;
