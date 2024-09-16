/* ==============================================================================
 * TEMPO High-Performance C Acceleration Extension
 *
 * Implements native C inner-loops for:
 * 1. 2D Bilinear NLDM Table Interpolation
 * 2. Roth 5-State D-Calculus Gate Evaluation
 * ==============================================================================
 */

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* Fast Bilinear Interpolation:
 * args: x y x0 x1 y0 y1 q00 q01 q10 q11
 */
static int Tempo_BilinearInterp_Cmd(ClientData clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    if (objc != 11) {
        Tcl_WrongNumArgs(interp, 1, objv, "x y x0 x1 y0 y1 q00 q01 q10 q11");
        return TCL_ERROR;
    }

    double x, y, x0, x1, y0, y1, q00, q01, q10, q11;
    if (Tcl_GetDoubleFromObj(interp, objv[1], &x) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[2], &y) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[3], &x0) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[4], &x1) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[5], &y0) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[6], &y1) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[7], &q00) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[8], &q01) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[9], &q10) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[10], &q11) != TCL_OK) return TCL_ERROR;

    double dx = x1 - x0;
    double dy = y1 - y0;

    /* Handle degenerate grid point boundaries */
    if (fabs(dx) < 1.0e-12 && fabs(dy) < 1.0e-12) {
        Tcl_SetObjResult(interp, Tcl_NewDoubleObj(q00));
        return TCL_OK;
    }
    if (fabs(dx) < 1.0e-12) {
        double r = (dy != 0.0) ? (q00 * (y1 - y) + q01 * (y - y0)) / dy : q00;
        Tcl_SetObjResult(interp, Tcl_NewDoubleObj(r));
        return TCL_OK;
    }
    if (fabs(dy) < 1.0e-12) {
        double r = (dx != 0.0) ? (q00 * (x1 - x) + q10 * (x - x0)) / dx : q00;
        Tcl_SetObjResult(interp, Tcl_NewDoubleObj(r));
        return TCL_OK;
    }

    double denom = dx * dy;
    double term1 = q00 * (x1 - x) * (y1 - y);
    double term2 = q10 * (x - x0) * (y1 - y);
    double term3 = q01 * (x1 - x) * (y - y0);
    double term4 = q11 * (x - x0) * (y - y0);

    double result = (term1 + term2 + term3 + term4) / denom;
    Tcl_SetObjResult(interp, Tcl_NewDoubleObj(result));
    return TCL_OK;
}

/* Fast Roth 5-State D-Calculus Gate Evaluation:
 * args: op in1 ?in2?
 */
static int Tempo_Roth5Gate_Cmd(ClientData clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    if (objc < 3 || objc > 4) {
        Tcl_WrongNumArgs(interp, 1, objv, "op in1 ?in2?");
        return TCL_ERROR;
    }

    const char *op = Tcl_GetString(objv[1]);
    const char *a_str = Tcl_GetString(objv[2]);
    const char *b_str = (objc == 4) ? Tcl_GetString(objv[3]) : "";

    char a = a_str[0];
    char b = b_str[0];
    if (a >= 'a' && a <= 'z') a = (char)(a - 32);
    if (b >= 'a' && b <= 'z') b = (char)(b - 32);

    /* Check for D_BAR (represented as 'B' or 'D_BAR') */
    int a_is_dbar = (strcmp(a_str, "D_BAR") == 0 || strcmp(a_str, "d_bar") == 0);
    int b_is_dbar = (strcmp(b_str, "D_BAR") == 0 || strcmp(b_str, "d_bar") == 0);
    if (a_is_dbar) a = 'B';
    if (b_is_dbar) b = 'B';

    const char *res = "X";

    if (strcmp(op, "not") == 0) {
        switch (a) {
            case '0': res = "1"; break;
            case '1': res = "0"; break;
            case 'D': res = "D_BAR"; break;
            case 'B': res = "D"; break;
            default:  res = "X"; break;
        }
    } else if (strcmp(op, "and") == 0) {
        if (a == '0' || b == '0') {
            res = "0";
        } else if (a == '1') {
            res = (b == 'B') ? "D_BAR" : (b == 'D' ? "D" : (b == '1' ? "1" : "X"));
        } else if (b == '1') {
            res = (a == 'B') ? "D_BAR" : (a == 'D' ? "D" : (a == '1' ? "1" : "X"));
        } else if (a == b) {
            res = (a == 'B') ? "D_BAR" : (a == 'D' ? "D" : "X");
        } else if ((a == 'D' && b == 'B') || (a == 'B' && b == 'D')) {
            res = "0";
        } else {
            res = "X";
        }
    } else if (strcmp(op, "or") == 0) {
        if (a == '1' || b == '1') {
            res = "1";
        } else if (a == '0') {
            res = (b == 'B') ? "D_BAR" : (b == 'D' ? "D" : (b == '0' ? "0" : "X"));
        } else if (b == '0') {
            res = (a == 'B') ? "D_BAR" : (a == 'D' ? "D" : (a == '0' ? "0" : "X"));
        } else if (a == b) {
            res = (a == 'B') ? "D_BAR" : (a == 'D' ? "D" : "X");
        } else if ((a == 'D' && b == 'B') || (a == 'B' && b == 'D')) {
            res = "1";
        } else {
            res = "X";
        }
    }

    Tcl_SetObjResult(interp, Tcl_NewStringObj(res, -1));
    return TCL_OK;
}

/* Package Initialization Routine */
int Tempo_accel_Init(Tcl_Interp *interp) {
    if (Tcl_InitStubs(interp, "8.6", 0) == NULL) {
        return TCL_ERROR;
    }

    Tcl_CreateObjCommand(interp, "::tempo::c::bilinear_interp", Tempo_BilinearInterp_Cmd, NULL, NULL);
    Tcl_CreateObjCommand(interp, "::tempo::c::roth5_gate", Tempo_Roth5Gate_Cmd, NULL, NULL);

    if (Tcl_PkgProvide(interp, "tempo_accel", "1.0") != TCL_OK) {
        return TCL_ERROR;
    }

    return TCL_OK;
}
