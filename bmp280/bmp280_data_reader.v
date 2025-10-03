module bmp280_data_reader(
    input wire clk,
    input wire rst,
    input wire start_read,
    input wire i2c_ready,
    input wire i2c_data_valid,
    input wire [7:0] i2c_data_in,

    output reg i2c_enable,
    output reg [7:0] i2c_reg_addr,
    output reg [3:0] i2c_bytes_to_read,
    
    output reg read_done,
    output reg [19:0] raw_temp_out,
    output reg [19:0] raw_press_out
);
    localparam S_IDLE = 0, S_START_READ = 1, S_WAIT_READ = 2;
    reg [1:0] state;
    reg [2:0] byte_counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            i2c_enable <= 1'b0;
            read_done <= 1'b0;
            byte_counter <= 0;
            raw_temp_out <= 0;
            raw_press_out <= 0;
        end else begin
            i2c_enable <= 1'b0;
            read_done <= 1'b0;

            case(state)
                S_IDLE: begin
                    if (start_read) begin
                        state <= S_START_READ;
                    end
                end

                S_START_READ: begin
                    if (i2c_ready) begin
                        i2c_reg_addr <= 8'hF7;
                        i2c_bytes_to_read <= 6;
                        i2c_enable <= 1'b1;
                        byte_counter <= 0;
                        state <= S_WAIT_READ;
                    end
                end

                S_WAIT_READ: begin
                    if (i2c_data_valid) begin
                        byte_counter <= byte_counter + 1;
                        case (byte_counter)
                            0: raw_press_out[19:12] <= i2c_data_in;
                            1: raw_press_out[11:4]  <= i2c_data_in;
                            2: raw_press_out[3:0]   <= i2c_data_in[7:4];
                            3: raw_temp_out[19:12]  <= i2c_data_in;
                            4: raw_temp_out[11:4]   <= i2c_data_in;
                            5: raw_temp_out[3:0]    <= i2c_data_in[7:4];
                        endcase
                    end
                    
                    if (i2c_ready && byte_counter == 6) begin
                        read_done <= 1'b1;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule