module i2c_master_controller(
    input wire clk,
    input wire rst,
    input wire [6:0] addr,
    input wire [7:0] reg_addr,
    input wire [7:0] wdata,
    input wire enable,
    input wire rw,
    input wire [3:0] bytes_to_read,

    output reg [7:0] data_out,
    output reg ready,
    output reg data_valid,
    
    inout wire i2c_sda,
    inout wire i2c_scl
);
    localparam CLK_DIV_HALF = 125;

    localparam S_IDLE=0, S_START_1=1, S_START_2=2, S_TX_BYTE=3, S_WAIT_SCL_H=4, S_WAIT_SCL_L=5,
               S_GET_ACK_1=6, S_GET_ACK_2=7, S_GET_ACK_3=8, S_STOP_1=9, S_STOP_2=10, S_STOP_3=11,
               S_REPEATED_START=12, S_RX_BYTE_WAIT_H=13, S_RX_BYTE_WAIT_L=14, 
               S_SEND_ACK_1=15, S_SEND_ACK_2=16, S_SEND_ACK_3=17, S_SEND_NACK_1=18;
    
    reg [4:0] state;
    reg [7:0] clk_count;
    reg [3:0] bit_count;
    reg [7:0] tx_buffer;
    reg [3:0] read_byte_counter;
    reg is_address_phase, is_reg_addr_phase, is_read_phase;
    reg scl_o, sda_o, sda_oe;

    assign i2c_scl = scl_o;
    assign i2c_sda = sda_oe ? sda_o : 1'bz;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            ready <= 1'b1;
            data_valid <= 1'b0;
            clk_count <= 0;
            bit_count <= 0;
            scl_o <= 1'b1;
            sda_o <= 1'b1;
            sda_oe <= 1'b1;
            data_out <= 8'h00;
            is_address_phase <= 1'b0;
            is_reg_addr_phase <= 1'b0;
            is_read_phase <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    ready <= 1'b1;
                    if (enable) begin
                        ready <= 1'b0;
                        tx_buffer <= {addr, 1'b0};
                        bit_count <= 8;
                        clk_count <= 0;
                        is_address_phase <= 1'b1;
                        is_reg_addr_phase <= 1'b0;
                        is_read_phase <= 1'b0;
                        state <= S_START_1;
                    end
                end

                S_START_1: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        sda_o <= 1'b0;
                        clk_count <= 0;
                        state <= S_START_2;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_START_2: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b0;
                        clk_count <= 0;
                        state <= S_TX_BYTE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_TX_BYTE: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        sda_o <= tx_buffer[bit_count-1];
                        clk_count <= 0;
                        state <= S_WAIT_SCL_H;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_WAIT_SCL_H: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b1;
                        clk_count <= 0;
                        state <= S_WAIT_SCL_L;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                S_WAIT_SCL_L: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
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
                    if (clk_count == CLK_DIV_HALF-1) begin
                        sda_oe <= 1'b0;
                        sda_o <= 1'b1;
                        clk_count <= 0;
                        state <= S_GET_ACK_2;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_GET_ACK_2: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b1;
                        clk_count <= 0;
                        state <= S_GET_ACK_3;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_GET_ACK_3: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b0;
                        sda_oe <= 1'b1;
                        clk_count <= 0;
                        if (i2c_sda) begin
                            state <= S_STOP_1;
                        end else begin
                            if (is_address_phase) begin
                                is_address_phase <= 0; is_reg_addr_phase <= 1;
                                tx_buffer <= reg_addr; bit_count <= 8; state <= S_TX_BYTE;
                            end else if (is_reg_addr_phase) begin
                                is_reg_addr_phase <= 0;
                                if (rw==0) begin
                                    tx_buffer <= wdata; bit_count <= 8; state <= S_TX_BYTE;
                                end else begin
                                    state <= S_REPEATED_START;
                                end
                            end else if (is_read_phase) begin
                                is_read_phase <= 0; bit_count <= 8; sda_oe <= 0;
                                read_byte_counter <= bytes_to_read; state <= S_RX_BYTE_WAIT_H;
                            end else begin
                                state <= S_STOP_1;
                            end
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_REPEATED_START: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b1; sda_o <= 1'b1; tx_buffer <= {addr,1'b1};
                        bit_count <= 8; is_read_phase <= 1; clk_count <= 0; state <= S_START_1;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_RX_BYTE_WAIT_H: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b1; clk_count <= 0; state <= S_RX_BYTE_WAIT_L;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                S_RX_BYTE_WAIT_L: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        data_out <= {data_out[6:0], i2c_sda};
                        scl_o <= 1'b0; clk_count <= 0; bit_count <= bit_count - 1;
                        if (bit_count == 1) begin
                            data_valid <= 1; sda_oe <= 1;
                            if (read_byte_counter > 1) begin
                                state <= S_SEND_ACK_1;
                            end else begin
                                state <= S_SEND_NACK_1;
                            end
                        end else begin
                            state <= S_RX_BYTE_WAIT_H;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                S_SEND_ACK_1: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        sda_o <= 1'b0; clk_count <= 0; state <= S_SEND_ACK_2;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_SEND_ACK_2: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b1; clk_count <= 0; state <= S_SEND_ACK_3;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_SEND_ACK_3: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b0; sda_oe <= 1'b0; clk_count <= 0; bit_count <= 8;
                        read_byte_counter <= read_byte_counter - 1; state <= S_RX_BYTE_WAIT_H;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                S_SEND_NACK_1: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        sda_o <= 1'b1; scl_o <= 1'b1; clk_count <= 0; state <= S_STOP_1;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_STOP_1: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        sda_o <= 1'b0; scl_o <= 1'b0; clk_count <= 0; state <= S_STOP_2;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_STOP_2: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        scl_o <= 1'b1; clk_count <= 0; state <= S_STOP_3;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                S_STOP_3: begin
                    if (clk_count == CLK_DIV_HALF-1) begin
                        sda_o <= 1'b1; state <= S_IDLE;
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