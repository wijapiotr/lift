/*
 * package for lift controller
 *
 * Defines structure used in interface
 */
package lift_pkg;

	typedef struct packed {
		logic up;
		logic down;
	} direction_t;

endpackage : lift_pkg