module lift_tb;

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Parameters and structures ////////////////////////////////////////////////////////////////////
	import lift_pkg::*;

	localparam int FLOOR_NUM = 16;
	localparam int STOP_DURATION = 10;
	localparam int FLOOR_NUM_WIDTH = $clog2(FLOOR_NUM);
	localparam int FLOOR_MODEL_LEN = 4;
	localparam int FLOOR_MODEL_STOP = FLOOR_MODEL_LEN / 2;
	localparam int FLOOR_MODEL_WIDTH = $clog2(FLOOR_MODEL_LEN);
	localparam int ITERATIONS = 1000;

	typedef struct packed {
		logic [FLOOR_NUM_WIDTH-1:0]   floor_id;
		logic [FLOOR_MODEL_WIDTH-1:0] stop_id; 
	} lift_possition_t;

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Signal declarations //////////////////////////////////////////////////////////////////////////
	logic                       clk;
	logic                       rst;
	direction_t [FLOOR_NUM-1:0] floors_direction; 
	logic       [FLOOR_NUM-1:0] floors_select; 
	logic       [FLOOR_NUM-1:0] lift_detector; 
	logic       [FLOOR_NUM-1:0] lift_stop_detector; 
	direction_t                 lift_engine; 
	direction_t [FLOOR_NUM-1:0] floors_direction_led; 
	logic       [FLOOR_NUM-1:0] floors_select_led; 

	int unsigned stop_cnt;

	bit [FLOOR_NUM-1:0] request_floor_led_pat;
	bit [FLOOR_NUM-1:0] request_lift_up_led_pat;
	bit [FLOOR_NUM-1:0] request_lift_down_led_pat;

	lift_possition_t lift_possition;

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// DUT instantion ///////////////////////////////////////////////////////////////////////////////
	lift #(
		.FLOOR_NUM           ( FLOOR_NUM            ),
		.STOP_DURATION       ( STOP_DURATION        )
	)
	dut (
		.clk                 ( clk                  ),
		.rst                 ( rst                  ),
		.floors_select_led   ( floors_select_led    ),
		.floors_direction_led( floors_direction_led ),
		.floors_select       ( floors_select        ),
		.lift_engine         ( lift_engine          ),
		.lift_detector       ( lift_detector        ),
		.floors_direction    ( floors_direction     ),
		.lift_stop_detector  ( lift_stop_detector   )
	);

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// clock and reset generation ///////////////////////////////////////////////////////////////////
	initial begin
		clk <= 1'b0;
		forever begin
			#2;
			clk <= !clk;
		end
	end

	initial begin
		rst <= 1'b1;
		repeat(2) @(posedge clk);
		rst <= 1'b0;
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// class with random button definition //////////////////////////////////////////////////////////
	class rand_button_impl;
		rand logic button;
		constraint c {
			// button activation probability
			button dist {0 := 50*FLOOR_NUM, 1:= 1};
		}
	endclass

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// random button object declaration /////////////////////////////////////////////////////////////
	rand_button_impl rand_button;

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// led patterns /////////////////////////////////////////////////////////////////////////////////
	always_ff @(posedge clk) begin
		if (rst) begin
			request_floor_led_pat <= '0;
			request_lift_up_led_pat <= '0;
			request_lift_down_led_pat <= '0;
		end
		else begin
			for (int i=0; i < FLOOR_NUM; i++) begin
				if (floors_select[i]) request_floor_led_pat[i] <= 1'b1;
				if (floors_direction[i].up) request_lift_up_led_pat[i] <= 1'b1;
				if (floors_direction[i].down) request_lift_down_led_pat[i] <= 1'b1;

				// floor is handled if the lift stops there for STOP_DURATION cycles
				if (lift_stop_detector[i] && stop_cnt == STOP_DURATION) begin
					request_floor_led_pat[i] <= 1'b0;
					request_lift_up_led_pat[i] <= 1'b0;
					request_lift_down_led_pat[i] <= 1'b0;
				end
			end
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// stimulus generation //////////////////////////////////////////////////////////////////////////
	initial begin
		rand_button = new();
		repeat(ITERATIONS) begin // in each cycle each request could be generated
			floors_select <= '0;
			floors_direction <= '0;
			foreach (floors_select[i]) begin
				if(!rand_button.randomize()) $fatal(1, "Randomize failed");
				floors_select[i] <= rand_button.button;
			end
			foreach (floors_direction[i]) begin
				if(!rand_button.randomize()) $fatal(1, "Randomize failed");
				floors_direction[i].up <= rand_button.button;
				if(!rand_button.randomize()) $fatal(1, "Randomize failed");
				floors_direction[i].down <= rand_button.button;
			end
			repeat(1) @(posedge clk);
		end
		// after ITERATIONS cycles there is wait to time where all request should be handled
		repeat((FLOOR_NUM*FLOOR_MODEL_LEN + FLOOR_NUM*STOP_DURATION) * 2) @(posedge clk);

		// check if all request are handled
		if (request_floor_led_pat || request_lift_up_led_pat || request_lift_down_led_pat) 
			$fatal(1, "There are not handled requests left");

		// finish the test
		$finish;
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// simple lift model ////////////////////////////////////////////////////////////////////////////
	always_ff @(posedge clk) begin
		if (rst) begin
			lift_possition <= '0;
		end
		else begin
			if (lift_engine.up) begin
				lift_possition <= lift_possition + 1;
			end
			if (lift_engine.down) begin
				lift_possition <= lift_possition - 1;
			end
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// generate signals for lift controler based on model ///////////////////////////////////////////
	always_comb begin
		lift_detector = '0;
		lift_detector[lift_possition.floor_id] = 1'b1;
		lift_stop_detector = '0;
		lift_stop_detector[lift_possition.floor_id] = (lift_possition.stop_id == FLOOR_MODEL_STOP);
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// basic checks /////////////////////////////////////////////////////////////////////////////////
	always_ff @(posedge clk) begin
		if (lift_stop_detector[0] && lift_engine.down) 
			$fatal(1, "lift should no go under floor 0");
		if (lift_stop_detector[FLOOR_NUM-1] && lift_engine.up) 
			$fatal(1, "lift should no go over last floor");
		for (int i=0; i < FLOOR_NUM; i++) begin
			if (request_floor_led_pat[i] != floors_select_led[i]) 
				$fatal(1, "floor %0d has wrong led signal", i);
			if (request_lift_up_led_pat[i] != floors_direction_led[i].up) 
				$fatal(1, "lift %0d has wrong up led signal", i);
			if (request_lift_down_led_pat[i] != floors_direction_led[i].down) 
				$fatal(1, "lift %0d has wrong down led signal", i);
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// counter how long the lift stays //////////////////////////////////////////////////////////////
	always_ff @(posedge clk) begin
		if (lift_engine) begin
			stop_cnt <= '0;
		end
		else begin
			if (stop_cnt < STOP_DURATION)
			stop_cnt <= stop_cnt + 1;
		end
	end

endmodule : lift_tb