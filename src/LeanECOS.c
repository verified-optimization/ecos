#include "LeanECOS.h"

#define BIAS 1023
#define MANTISA_BITS 52
#define EXPONENT_BITS 11
#define SIGN_BITS 1

typedef union {
  double f;
  struct {
    unsigned int long mantisa : MANTISA_BITS;
    unsigned int exponent : EXPONENT_BITS;
    unsigned int sign : SIGN_BITS;
  } parts;
} float_cast;


/***** Running the solver with different floattypes / boxing. *****/

lean_object * run_solver_unboxed_generic(lean_object * o, enum FloatType ti, enum FloatType to) {
    lean_object * n_o      = lean_ctor_get(o, 0);
    lean_object * m_o      = lean_ctor_get(o, 1); 
    lean_object * p_o      = lean_ctor_get(o, 2); 
    lean_object * l_o      = lean_ctor_get(o, 3);
    lean_object * ncones_o = lean_ctor_get(o, 4);  
    lean_object * q_o      = lean_ctor_get(o, 5);
    lean_object * e_o      = lean_ctor_get(o, 6);
    lean_object * G_o      = lean_ctor_get(o, 7);
    lean_object * A_o      = lean_ctor_get(o, 8);
    lean_object * c_o      = lean_ctor_get(o, 9);
    lean_object * h_o      = lean_ctor_get(o, 10);
    lean_object * b_o      = lean_ctor_get(o, 11);

    idxint   n      = read_lean_int(n_o);
    idxint   m      = read_lean_int(m_o);
    idxint   p      = read_lean_int(p_o);
    idxint   l      = read_lean_int(l_o);
    idxint   ncones = read_lean_int(ncones_o);
    idxint * q      = read_lean_int_array(q_o, ncones);
    idxint   e      = read_lean_int(e_o);
    spmat *  G      = read_lean_floattype_sparse_matrix(G_o, ti);
    spmat *  A      = read_lean_floattype_sparse_matrix(A_o, ti);
    pfloat * c      = read_lean_floattype_array(c_o, n, ti);
    pfloat * h      = read_lean_floattype_array(h_o, m, ti);
    pfloat * b      = read_lean_floattype_array(b_o, p, ti);

    pwork* work;
    idxint exitflag;

    work = ECOS_setup(n, m, p,
        l, ncones, q, e,
        G->pr, G->jc, G->ir,
        A->pr, A->jc, A->ir,
        c, h, b);

    if (work != NULL) {
        exitflag = ECOS_solve(work); 
    } 
    else {
        exitflag = ECOS_FATAL;
    }

    lean_object * exitflag_o = write_lean_int(exitflag);
    lean_object * cx_o;
    lean_object * x_o;

    if (exitflag == ECOS_OPTIMAL) {
        cx_o = write_lean_floattype(work->cx, to);
        x_o  = write_lean_floattype_array(work->x, n, to);
    } 
    else {
        cx_o = write_lean_floattype(0.0, to);
        x_o  = write_lean_floattype_array(NULL, 0, to);
    }    

    lean_object * result_o = lean_alloc_ctor(0, 3, 0);
    lean_ctor_set(result_o, 0, exitflag_o);
    lean_ctor_set(result_o, 1, cx_o);
    lean_ctor_set(result_o, 2, x_o);

    if (work != NULL) {
        ECOS_cleanup(work, 0);
    }

    return result_o;
}

lean_object * run_solver_dyadic_dyadic_unboxed(lean_object * o) {
    return run_solver_unboxed_generic(o, Dyadic, Dyadic);
}

lean_object * run_solver_dyadic_dyadic(lean_object * o) {
    return lean_io_result_mk_ok(run_solver_dyadic_dyadic_unboxed(o));
}

lean_object * run_solver_float_float_unboxed(lean_object * o) {
    return run_solver_unboxed_generic(o, Float, Float);
}

lean_object * run_solver_float_float(lean_object * o) {
    return lean_io_result_mk_ok(run_solver_float_float_unboxed(o));
}

lean_object * run_solver_float_dyadic_unboxed(lean_object * o) {
    return run_solver_unboxed_generic(o, Float, Dyadic);
}

lean_object * run_solver_float_dyadic(lean_object * o) {
    return lean_io_result_mk_ok(run_solver_float_dyadic_unboxed(o));
}

/***** Reading Lean objects *****/

// Integers.

idxint read_lean_int(lean_object * o) {
    return (idxint) lean_scalar_to_int(o);
}

// Floattypes.

pfloat read_lean_dyadic(lean_object * o) {
    lean_object * m_o = lean_ctor_get(o, 0);
    lean_object * e_o = lean_ctor_get(o, 1);

    double m = (double) lean_scalar_to_int(m_o);
    double e = (double) lean_scalar_to_int(e_o);

    return (pfloat) (m * pow(2, e));
}

pfloat read_lean_float(lean_object * o) {
    return (pfloat) lean_unbox_float(o);
}

pfloat read_lean_floattype(lean_object * o, enum FloatType t) {
    if (t == Dyadic) {
        return read_lean_dyadic(o);
    } 
    else if (t == Float) {
        return read_lean_float(o);
    }
}

// Integer arrays.

idxint * read_lean_int_array(lean_object * o, idxint n) {
    if (n == 0) {
        return NULL;
    }

    idxint * result = malloc(n * sizeof(idxint));

    for (int i = 0; i < n; i++) {
        lean_object * elem = lean_array_get_core(o, i);
        result[i] = read_lean_int(elem);
    }

    return result;
}

// Floattype arrays.

pfloat * read_lean_floattype_array(lean_object * o, idxint n, enum FloatType t) {
    if (n == 0) {
        return NULL;
    }

    pfloat * result = malloc(n * sizeof(pfloat));

    for (int i = 0; i < n; i++) {
        lean_object * elem = lean_array_get_core(o, i);
        result[i] = read_lean_floattype(elem, t);
    }

    return result;
}

pfloat * read_lean_dyadic_array(lean_object * o, idxint n) {
    return read_lean_floattype_array(o, n, Dyadic);
}

pfloat * read_lean_float_array(lean_object * o, idxint n) {
    return read_lean_floattype_array(o, n, Float);
}

// Sparse matrices.

spmat * read_lean_floattype_sparse_matrix(lean_object * o, enum FloatType t) {
    lean_object * nnz_o    = lean_ctor_get(o, 0); 
    lean_object * n_o      = lean_ctor_get(o, 1); 
    lean_object * val_o    = lean_ctor_get(o, 2); 
    lean_object * rowIdx_o = lean_ctor_get(o, 3); 
    lean_object * colPtr_o = lean_ctor_get(o, 4); 

    idxint   nnz    = read_lean_int(nnz_o);
    idxint   n      = read_lean_int(n_o);
    pfloat * val    = read_lean_floattype_array(val_o, nnz, t);
    idxint * rowIdx = read_lean_int_array(rowIdx_o, nnz);
    // TODO: This is just a trick to handle empty spmat's.
    idxint * colPtr = read_lean_int_array(colPtr_o, n > 0 ? n + 1 : 0); 

    // Max row index is the number of rows - 1.
    idxint m = 0;
    for (int i = 0; i < nnz; i++) {
        if (rowIdx[i] > m) {
            m = rowIdx[i];
        }
    }

    spmat * result = newSparseMatrix(m + 1, n, nnz);
    result->pr = val;
    result->ir = rowIdx;
    result->jc = colPtr;

    return result;
}

spmat * read_lean_dyadic_sparse_matrix(lean_object * o) {
    return read_lean_floattype_sparse_matrix(o, Dyadic);
}

spmat * read_lean_float_sparse_matrix(lean_object * o) {
    return read_lean_floattype_sparse_matrix(o, Float);
}


/***** Writing Lean objects *****/

// Integers.

lean_object * write_lean_int(idxint i) {
    return lean_int_to_int((int) i);
}

// Floattypes.

lean_object * write_lean_dyadic(pfloat f) {
    float_cast x = { .f = (double) f };
    
    int s, e;
    int64_t m;

    s = x.parts.sign == 1 ? -1 : 1;
    if (x.parts.mantisa == 0) {
        e = 0;
        m = 0;
    } 
    else {
        e = x.parts.exponent - BIAS - MANTISA_BITS;
        m = s * (x.parts.mantisa + (1UL << MANTISA_BITS));
    }

    lean_object * m_o = lean_big_int64_to_int(m);
    lean_object * e_o = lean_int_to_int(e);

    lean_object * result = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(result, 0, m_o);
    lean_ctor_set(result, 1, e_o);

    return result;
}

lean_object * write_lean_float(pfloat f) {
    return lean_box_float((double) f);
}

lean_object * write_lean_floattype(pfloat f, enum FloatType t) {
    if (t == Dyadic) {
        return write_lean_dyadic(f);
    }
    else if (t == Float) {
        return write_lean_float(f);
    }
}

// Floattype arrays.

lean_object * write_lean_floattype_array(pfloat * a, idxint n, enum FloatType t) {
    lean_object * result = lean_alloc_array(0, n);
    
    for (int i = 0; i < n; i++) {
        lean_object * a_i_o = write_lean_floattype(a[i], t);
        lean_array_push(result, a_i_o);
    }

    return result;
}

lean_object * write_lean_dyadic_array(pfloat * a, idxint n) {
    return write_lean_floattype_array(a, n, Dyadic);
}

lean_object * write_lean_float_array(pfloat * a, idxint n) {
    return write_lean_floattype_array(a, n, Float);
}
