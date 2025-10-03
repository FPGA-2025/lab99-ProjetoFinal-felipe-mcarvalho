module top_module (
    input wire sys_clk,
    input wire sys_rst,
    inout wire i2c_scl,
    inout wire i2c_sda
);

    // --- Sinais internos ---
    wire rst_internal;
    reg  [6:0] addr_reg;
    reg  [7:0] data_in_reg;
    reg  enable_reg;
    reg  rw_reg;
    wire [7:0] data_out_wire;
    wire ready_wire; // Informa se o I2C ta ocupado ou nao

    assign rst_internal = ~sys_rst;

    // --- Controlador I2C ---
    i2c_controller u_i2c_controller (
        .clk        (sys_clk),
        .rst        (rst_internal),
        .addr       (addr_reg),
        .wdata      (data_in_reg),
        .enable     (enable_reg),
        .rw         (rw_reg),
        .data_out   (data_out_wire),
        .ready      (ready_wire),
        .i2c_sda    (i2c_sda),
        .i2c_scl    (i2c_scl)
    );

    // --- Parametros de Atraso (Clock de 25MHz) ---
    // Sequencia tem 16 estados (14 para init + 2 para o caractere)
    localparam SEQ_LEN           = 16;
    localparam LSN_CMD_BASE      = 4'b1000; // RS=0 (Comando), BL=1
    localparam LSN_DATA_BASE     = 4'b1001; // RS=1 (Dados/Caractere), BL=1
    localparam LSN_PULSO         = 4'b0100; // Mascara para E=1
    
    // Defina o caractere a ser escrito aqui
    localparam CHAR_TO_WRITE     = "A"; 
    
    localparam INIT_DELAY_CYCLES = 1250000; // 50ms
    localparam DELAY_RESET       = 125000;  // 5ms
    localparam DELAY_CLEAR       = 50000;   // 2ms
    localparam DELAY_NORMAL      = 2500;    // 100us

    // --- Maquina de Estados do Sequenciador 
    localparam S_IDLE       = 4'b0000;
    localparam S_SETUP_TX   = 4'b0001;
    localparam S_WAIT_START = 4'b0010;
    localparam S_WAIT_DONE  = 4'b0011;
    localparam S_DELAY      = 4'b0100;
    localparam S_DONE       = 4'b0101;

    reg [3:0] state;

    reg [$clog2(SEQ_LEN)-1:0] nibble_index;
    reg [1:0] pulse_step;
    reg [23:0] delay_counter;
    reg init_delay_done;

    // --- Sequencia e Atrasos 
    wire [3:0] current_msn;
    wire [23:0] current_delay;
    // --- Sinal para selecionar o modo Comando (RS=0) ou Dados (RS=1)
    wire [3:0] current_lsn_base;

    // --- Sequencia de inicializacao
    assign current_msn = (nibble_index == 0)  ? 4'h3 :                  // Reset
                         (nibble_index == 1)  ? 4'h3 :                  // Reset
                         (nibble_index == 2)  ? 4'h3 :                  // Reset
                         (nibble_index == 3)  ? 4'h2 :                  // Set 4-bit mode
                         (nibble_index == 4)  ? 4'h2 :                  // Function Set (MSN)
                         (nibble_index == 5)  ? 4'h8 :                  // Function Set (LSN) -> 0x28
                         (nibble_index == 6)  ? 4'h0 :                  // Display OFF (MSN)
                         (nibble_index == 7)  ? 4'h8 :                  // Display OFF (LSN) -> 0x08
                         (nibble_index == 8)  ? 4'h0 :                  // Clear Display (MSN)
                         (nibble_index == 9)  ? 4'h1 :                  // Clear Display (LSN) -> 0x01
                         (nibble_index == 10) ? 4'h0 :                  // Entry Mode Set (MSN)
                         (nibble_index == 11) ? 4'h6 :                  // Entry Mode Set (LSN) -> 0x06
                         (nibble_index == 12) ? 4'h0 :                  // Display ON (MSN)
                         (nibble_index == 13) ? 4'hF :                  // Display ON (LSN) -> 0x0F
                         (nibble_index == 14) ? CHAR_TO_WRITE[7:4] :    // Caractere MSN
                         (nibble_index == 15) ? CHAR_TO_WRITE[3:0] :    // Caractere LSN
                         4'h0;

    // --- Seleciona RS=1 apenas para os ultimos 2 nibbles (o caractere)
    assign current_lsn_base = (nibble_index < 14) ? LSN_CMD_BASE : LSN_DATA_BASE;
                         
    // --- Logica de delay 
    assign current_delay = (nibble_index == 0) ? DELAY_RESET :
                           (nibble_index == 9) ? DELAY_CLEAR :
                           DELAY_NORMAL;

    always @(posedge sys_clk or negedge sys_rst) begin
        if (!sys_rst) begin 
            state <= S_IDLE;
            enable_reg <= 1'b0;
            addr_reg <= 7'h27;
            rw_reg <= 1'b0;
            data_in_reg <= 8'h00;
            nibble_index <= 0;
            pulse_step <= 0;
            delay_counter <= 0;
            init_delay_done <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (!init_delay_done) begin
                        if (delay_counter < INIT_DELAY_CYCLES - 1) begin
                            delay_counter <= delay_counter + 1;
                        end else begin
                            init_delay_done <= 1'b1;
                        end
                    end
                    else if (ready_wire) begin 
                        state <= S_SETUP_TX;
                    end
                end
                
                S_SETUP_TX: begin
                    if (pulse_step == 1) begin
                        data_in_reg <= {current_msn, (current_lsn_base | LSN_PULSO)};
                    end else begin
                        data_in_reg <= {current_msn, current_lsn_base};
                    end
                    enable_reg <= 1'b1; 
                    state <= S_WAIT_START;
                end

                S_WAIT_START: begin
                    if (~ready_wire) begin
                        enable_reg <= 1'b0;
                        state <= S_WAIT_DONE;
                    end
                end

                S_WAIT_DONE: begin
                    if (ready_wire) begin
                        if (pulse_step == 2) begin
                            pulse_step <= 0;
                            delay_counter <= 0;
                            state <= S_DELAY;
                        end else begin
                            pulse_step <= pulse_step + 1;
                            state <= S_SETUP_TX;
                        end
                    end
                end
                
                S_DELAY: begin
                    if (delay_counter >= current_delay - 1) begin
                        if (nibble_index == SEQ_LEN - 1) begin
                            state <= S_DONE;
                        end else begin
                            nibble_index <= nibble_index + 1;
                            state <= S_SETUP_TX;
                        end
                    end else begin
                        delay_counter <= delay_counter + 1;
                    end
                end
                
                S_DONE: begin
                    state <= S_DONE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule