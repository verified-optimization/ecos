#pragma once
#include <lean/lean.h>
#include <lean/lean_gmp.h>

#include "ecos.h"
#include "splamm.h"

enum FloatType {Dyadic = 0, Float = 1};

lean_object * run_solver_unboxed_generic(lean_object * o, enum FloatType ti, enum FloatType to);
lean_object * run_solver_dyadic_dyadic_unboxed(lean_object * o);
lean_object * run_solver_dyadic_dyadic(lean_object * o);
lean_object * run_solver_float_float_unboxed(lean_object * o);
lean_object * run_solver_float_float(lean_object * o);
lean_object * run_solver_float_dyadic_unboxed(lean_object * o);
lean_object * run_solver_float_dyadic(lean_object * o);

idxint   read_lean_int(lean_object * o);
pfloat   read_lean_dyadic(lean_object * o);
pfloat   read_lean_float(lean_object * o);
pfloat   read_lean_floattype(lean_object * o, enum FloatType t);
idxint * read_lean_int_array(lean_object * o, idxint n);
pfloat * read_lean_floattype_array(lean_object * o, idxint n, enum FloatType t);
pfloat * read_lean_dyadic_array(lean_object * o, idxint n);
pfloat * read_lean_float_array(lean_object * o, idxint n);
spmat *  read_lean_floattype_sparse_matrix(lean_object * o, enum FloatType t);
spmat *  read_lean_dyadic_sparse_matrix(lean_object * o);
spmat * read_lean_float_sparse_matrix(lean_object * o);

lean_object * write_lean_int(idxint i);
lean_object * write_lean_dyadic(pfloat f);
lean_object * write_lean_float(pfloat f);
lean_object * write_lean_floattype(pfloat f, enum FloatType t);
lean_object * write_lean_floattype_array(pfloat * a, idxint n, enum FloatType t);
lean_object * write_lean_dyadic_array(pfloat * a, idxint n);
lean_object * write_lean_float_array(pfloat * a, idxint n);
