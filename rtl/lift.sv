/*
 * lift controller
 *
 * It assumes that all inputs are synchronized to clk and debouncer is not needed
 * (if inputs would be asynchronous, inputs needs to be probe on clk and simple
 * shift register could be used as debouncer)
 * It also assumes that the lift will stop for STOP_DURATION cycles
 */

module lift #(
	// floors number
	parameter int FLOOR_NUM = 16,
	// lift will stop for STOP_DURATION cycles
	parameter int STOP_DURATION = 10,
	// lift will stop exacly when lift_stop_detector is asserted
	// but the logic is asynchronous because of that
	parameter int MAKE_STOP_ASYNC = 1
)
(
	input  logic                                 clk,
	input  logic                                 rst,

	// request buttons on the floors
	input  lift_pkg::direction_t [FLOOR_NUM-1:0] floors_direction,
	// request buttons inside lift
	input  logic                 [FLOOR_NUM-1:0] floors_select,
	// detects where is the lift. onehot
	input  logic                 [FLOOR_NUM-1:0] lift_detector,
	// detects if the list is exacly in stop place
	input  logic                 [FLOOR_NUM-1:0] lift_stop_detector,

	// engine controller
	output lift_pkg::direction_t                 lift_engine,
	// marks which directions are choosen on the floors
	output lift_pkg::direction_t [FLOOR_NUM-1:0] floors_direction_led,
	// marks which floors are choosen inside lift
	output logic                 [FLOOR_NUM-1:0] floors_select_led
);
	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Parameter declaration ////////////////////////////////////////////////////////////////////////
	localparam int STOP_DURATION_WIDTH = $clog2(STOP_DURATION);

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Enum declaration /////////////////////////////////////////////////////////////////////////////
	typedef enum logic[1:0] {
		IDLE,
		UP,
		DOWN
	} state_t;

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Signals declarations /////////////////////////////////////////////////////////////////////////
	state_t state;
	logic is_seleced_above;
	logic is_seleced_below;
	logic stop;
	logic stop_request;
	logic [STOP_DURATION_WIDTH-1:0] stop_cnt;
	logic lift_in_the_stop_possition;

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Control buttons on the floors ////////////////////////////////////////////////////////////////
	always_ff @(posedge clk) begin : DIR_LED
		if (rst) begin
			floors_direction_led <= '0;
		end
		else begin
			for (int i=0; i < FLOOR_NUM; i++) begin
				if (floors_direction[i].up) begin
					floors_direction_led[i].up <= 1'b1;
				end
				if (floors_direction[i].down) begin
					floors_direction_led[i].down <= 1'b1;
				end
				if (lift_stop_detector[i] && !stop_cnt) begin
					floors_direction_led[i].up   <= 1'b0;
					floors_direction_led[i].down <= 1'b0;
				end
			end
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Control buttons in the lift //////////////////////////////////////////////////////////////////
	always_ff @(posedge clk) begin
		if (rst) begin
			floors_select_led <= '0;
		end
		else begin
			for (int i=0; i < FLOOR_NUM; i++) begin
				if (floors_select[i]) begin
					floors_select_led[i] <= 1'b1;
				end
				if (lift_stop_detector[i] && !stop_cnt) begin
					floors_select_led[i] <= 1'b0;
				end
			end
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Main state machine ///////////////////////////////////////////////////////////////////////////
	// Changing direction is going throw IDLE state because it still be fast enaugh
	always_ff @(posedge clk) begin
		if (rst) begin
			state <= IDLE;
		end
		else begin
			case (state)
				IDLE: begin
					if (is_seleced_above) begin
						state <= UP;
					end
					else if (is_seleced_below) begin
						state <= DOWN;
					end
				end
				UP: begin
					if (!is_seleced_above && lift_in_the_stop_possition) begin
						state <= IDLE;
					end
				end
				DOWN: begin
					if (!is_seleced_below && lift_in_the_stop_possition) begin
						state <= IDLE;
					end
				end
			endcase
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Function to detect if there is any need to go up /////////////////////////////////////////////
	bit above_current_floor_passed;
	always_comb begin
		is_seleced_above = 1'b0;
		above_current_floor_passed = 1'b0;
		for (int i=0; i < FLOOR_NUM; i++) begin
			if (above_current_floor_passed &&
					(floors_direction_led[i].down)) begin
				is_seleced_above = 1'b1;
			end
			if (above_current_floor_passed && i != (FLOOR_NUM - 1) &&
					(floors_direction_led[i].up || floors_select_led[i])) begin
				is_seleced_above = 1'b1;
			end
			if (lift_detector[i]) begin
				above_current_floor_passed = 1'b1;
			end
			if (above_current_floor_passed && i == (FLOOR_NUM - 1) &&
					(floors_direction_led[i].up || floors_select_led[i])) begin
				is_seleced_above = 1'b1;
			end
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Function to detect if there is any need to go down ///////////////////////////////////////////
	bit below_current_floor_passed;
	always_comb begin
		is_seleced_below = 1'b0;
		below_current_floor_passed = 1'b0;
		for (int i=0; i < FLOOR_NUM; i++) begin
			if (!below_current_floor_passed &&
					(floors_direction_led[i].down || floors_select_led[i])) begin
				is_seleced_below = 1'b1;
			end
			if (!below_current_floor_passed && i != 0 &&
					(floors_direction_led[i].up)) begin
				is_seleced_below = 1'b1;
			end
			if (lift_detector[i]) begin
				below_current_floor_passed = 1'b1;
			end
			if (!below_current_floor_passed && i == 0 &&
					(floors_direction_led[i].up)) begin
				is_seleced_below = 1'b1;
			end
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Drive engine controls ////////////////////////////////////////////////////////////////////////
	always_comb begin
		if (MAKE_STOP_ASYNC) begin
			lift_engine.up   = state == UP   && !stop_request && !stop && !lift_stop_detector[FLOOR_NUM-1];
			lift_engine.down = state == DOWN && !stop_request && !stop && !lift_stop_detector[0];
		end
		else begin
			lift_engine.up   = state == UP   && !stop;
			lift_engine.down = state == DOWN && !stop;
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Stop control /////////////////////////////////////////////////////////////////////////////////
	always_comb begin
		lift_in_the_stop_possition = 1'b0;
		for (int i=0; i < FLOOR_NUM; i++) begin
			if (lift_stop_detector[i]) begin
				lift_in_the_stop_possition = 1'b1;
			end
		end
	end

	/////////////////////////////////////////////////////////////////////////////////////////////////
	// Stop control /////////////////////////////////////////////////////////////////////////////////
	always_comb begin
		stop_request = 1'b0;
		for (int i=0; i < FLOOR_NUM; i++) begin
			if (lift_stop_detector[i] &&
				 		(floors_select_led[i] ||
						(floors_direction_led[i].up && state == UP) ||
						(floors_direction_led[i].down && state == DOWN))) begin
				stop_request = 1'b1;
			end
		end
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			stop <= 1'b0;
		end
		else begin
			if (stop_request) begin
				stop <= 1'b1;
			end
			else if (!stop_cnt) begin
				stop <= 1'b0;
			end
		end
	end

	always_ff @(posedge clk) begin
		if (lift_engine) begin
			stop_cnt <= STOP_DURATION;
		end
		else if (stop_cnt) begin
			stop_cnt <= stop_cnt - 1;
		end
	end

endmodule : lift