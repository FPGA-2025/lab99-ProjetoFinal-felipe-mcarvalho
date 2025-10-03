module top_module (
    input wire sys_clk,
    input wire sys_rst,
    inout wire i2c_scl,
    inout wire i2c_sda
);
    wire rst = ~sys_rst;

    wire init_done;
    reg  start_read_data;
    wire read_data_done;

    wire        i2c_enable_from_init, i2c_enable_from_reader;
    wire [7:0]  i2c_wdata_from_init;
    wire [7:0]  i2c_reg_addr_from_init, i2c_reg_addr_from_reader;
    wire [3:0]  i2c_bytes_to_read_from_reader;
    wire        i2c_rw_from_init;
    
    wire [7:0]  i2c_data_out;
    wire        i2c_ready;
    wire        i2c_data_valid;

    reg         i2c_enable;
    reg [6:0]   i2c_addr;
    reg [7:0]   i2c_reg_addr;
    reg [7:0]   i2c_wdata;
    reg         i2c_rw;
    reg [3:0]   i2c_bytes_to_read;
    
    i2c_master_controller u_i2c_master (
        .clk(sys_clk), .rst(rst), .addr(i2c_addr), .reg_addr(i2c_reg_addr),
        .wdata(i2c_wdata), .enable(i2c_enable), .rw(i2c_rw), .bytes_to_read(i2c_bytes_to_read),
        .data_out(i2c_data_out), .ready(i2c_ready), .data_valid(i2c_data_valid),
        .i2c_sda(i2c_sda), .i2c_scl(i2c_scl)
    );

    bmp280_init_controller u_initializer (
        .clk(sys_clk), .rst(rst), .start_initialization(~init_done), .init_done(init_done),
        .chip_id_out(), .i2c_enable(i2c_enable_from_init), .i2c_reg_addr(i2c_reg_addr_from_init),
        .i2c_wdata(i2c_wdata_from_init), .i2c_rw(i2c_rw_from_init), .i2c_data_in(i2c_data_out), .i2c_ready(i2c_ready));

    bmp280_data_reader u_data_reader (
        .clk(sys_clk), .rst(rst), .start_read(start_read_data), .i2c_ready(i2c_ready), 
        .i2c_data_valid(i2c_data_valid), .i2c_data_in(i2c_data_out), .i2c_enable(i2c_enable_from_reader), 
        .i2c_reg_addr(i2c_reg_addr_from_reader), .i2c_bytes_to_read(i2c_bytes_to_read_from_reader),
        .read_done(read_data_done), .raw_temp_out(), .raw_press_out());

    localparam S_INIT = 0, S_RUN = 1, S_WAIT = 2;
    reg [1:0] main_state;
    reg [24:0] wait_counter;

    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            main_state <= S_INIT;
            start_read_data <= 0;
            wait_counter <= 0;
        end else begin
            start_read_data <= 1'b0;

            case (main_state)
                S_INIT: begin
                    i2c_addr <= 7'h76;
                    i2c_enable <= i2c_enable_from_init;
                    i2c_reg_addr <= i2c_reg_addr_from_init;
                    i2c_wdata <= i2c_wdata_from_init;
                    i2c_rw <= i2c_rw_from_init;
                    i2c_bytes_to_read <= 1;
                    
                    if (init_done) begin
                        main_state <= S_RUN;
                    end
                end
                
                S_RUN: begin
                    i2c_addr <= 7'h76;
                    i2c_enable <= i2c_enable_from_reader;
                    i2c_reg_addr <= i2c_reg_addr_from_reader;
                    i2c_wdata <= 8'h00;
                    i2c_rw <= 1'b1;
                    i2c_bytes_to_read <= i2c_bytes_to_read_from_reader;
                    
                    start_read_data <= 1'b1;
                    main_state <= S_WAIT;
                end

                S_WAIT: begin
                    i2c_addr <= 7'h76;
                    i2c_enable <= i2c_enable_from_reader;
                    i2c_reg_addr <= i2c_reg_addr_from_reader;
                    i2c_wdata <= 8'h00;
                    i2c_rw <= 1'b1;
                    i2c_bytes_to_read <= i2c_bytes_to_read_from_reader;

                    if (read_data_done || wait_counter > 0) begin
                        wait_counter <= wait_counter + 1;
                    end

                    if (wait_counter >= 25_000_000) begin
                        main_state <= S_RUN;
                        wait_counter <= 0;
                    end
                end
            endcase
        end
    end
endmodule