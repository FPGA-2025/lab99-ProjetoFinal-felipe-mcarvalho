
// START -> ENDERECO+RW -> DADO -> STOP

module i2c_controller(
    input wire clk,         
    input wire rst,         
    input wire [6:0] addr,  
    input wire [7:0] wdata, 
    input wire enable,     // Pulso para iniciar a transacao
    input wire rw,          
    
    output reg [7:0] data_out, 
    output reg ready,      // Controlador pronto para nova transacao, 0: Ocupado
    
    // Interface Fisica I2C
    inout wire i2c_sda,
    inout wire i2c_scl
);

    // --- Parametros de Timing ---
    localparam CLK_DIV_HALF = 125;

    // --- Estados da Maquina de Controle ---
    localparam S_IDLE       = 0;
    localparam S_START_1    = 1;
    localparam S_START_2    = 2;
    localparam S_TX_BYTE    = 3;
    localparam S_WAIT_SCL_H = 4;
    localparam S_WAIT_SCL_L = 5;
    localparam S_GET_ACK_1  = 6;
    localparam S_GET_ACK_2  = 7;
    localparam S_GET_ACK_3  = 8;
    localparam S_STOP_1     = 9;
    localparam S_STOP_2     = 10;
    localparam S_STOP_3     = 11;
    
    // --- Registradores Internos ---
    reg [3:0]  state;
    reg [7:0]  clk_count;
    reg [3:0]  bit_count;
    reg [7:0]  tx_buffer;
    reg [7:0]  rx_buffer;
    reg        ack_error;
    reg        is_address_phase; // Flag para diferenciar a fase de endereco da de dados

    // --- Controle dos Pinos Fisicos ---
    reg scl_o;
    reg sda_o;
    reg sda_oe;
   
    assign i2c_scl = scl_o;
    assign i2c_sda = sda_oe ? sda_o : 1'bz;

    // --- Maquina de Estados ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            ready <= 1'b1;
            clk_count <= 0;
            bit_count <= 0;
            scl_o <= 1'b1;
            sda_o <= 1'b1; 
            sda_oe <= 1'b1;
            ack_error <= 1'b0;
            data_out <= 8'h00;
            is_address_phase <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin // O estado idle do i2c fica preparado, caso seja ativado, ele da um setup
                    ready <= 1'b1;
                    ack_error <= 1'b0;
                    if (enable) begin 
                        ready <= 1'b0;
                        tx_buffer <= {addr, rw};
                        bit_count <= 8;
                        clk_count <= 0;
                        is_address_phase <= 1'b1; // Inicia a fase de enderco
                        state <= S_START_1;
                    end
                end

                S_START_1: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        sda_o <= 1'b0;
                        clk_count <= 0;
                        state <= S_START_2;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_START_2: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        scl_o <= 1'b0;
                        clk_count <= 0;
                        state <= S_TX_BYTE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_TX_BYTE: begin
                     if (clk_count == CLK_DIV_HALF - 1) begin
                        sda_o <= tx_buffer[bit_count-1];
                        clk_count <= 0;
                        state <= S_WAIT_SCL_H;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_WAIT_SCL_H: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        scl_o <= 1'b1;
                        clk_count <= 0;
                        state <= S_WAIT_SCL_L;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                S_WAIT_SCL_L: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        scl_o <= 1'b0;
                        clk_count <= 0;
                        bit_count <= bit_count - 1;
                        if (bit_count == 1) begin
                            state <= S_GET_ACK_1;
                        end else begin
                            state <= S_TX_BYTE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_GET_ACK_1: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        sda_o <= 1'b1;
                        sda_oe <= 1'b0;
                        clk_count <= 0;
                        state <= S_GET_ACK_2;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_GET_ACK_2: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        scl_o <= 1'b1;
                        clk_count <= 0;
                        state <= S_GET_ACK_3;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_GET_ACK_3: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        ack_error <= i2c_sda;
                        scl_o <= 1'b0;
                        sda_oe <= 1'b1;
                        clk_count <= 0;
                        
                        if (i2c_sda) begin
                            state <= S_STOP_1;
                        end else begin
                            if (is_address_phase) begin
                                is_address_phase <= 1'b0;
                                if (rw == 1'b0) begin
                                    tx_buffer <= wdata;
                                    bit_count <= 8;
                                    state <= S_TX_BYTE;
                                end else begin
                                    state <= S_STOP_1;
                                end
                            end else begin // Fim da fase de dados, vai para STOP
                                state <= S_STOP_1;
                            end
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                S_STOP_1: begin
                     if (clk_count == CLK_DIV_HALF - 1) begin
                        sda_o <= 1'b0;
                        clk_count <= 0;
                        state <= S_STOP_2;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_STOP_2: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        scl_o <= 1'b1;
                        clk_count <= 0;
                        state <= S_STOP_3;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_STOP_3: begin
                    if (clk_count == CLK_DIV_HALF - 1) begin
                        sda_o <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

