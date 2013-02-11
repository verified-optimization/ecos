function [x,y,info,s,z] = conelp(c,G,h,dims,A,b)
% Self-dual homogeneous embedding interior point method for optimization
% over linear or second-order cones. No SDP cones supported!
%
%  out = conelp(c, G, h, dims, A, b)
%    Solves a pair of primal and dual cone programs
% 
%        minimize    c'*x
%        subject to  G*x + s = h
%                    A*x = b
%                    s >= 0
%
%        maximize    -h'*z - b'*y
%        subject to  G'*z + A'*y + c = 0
%                    z >= 0.
%
%    The inequalities are with respect to a cone C defined as the Cartesian
%    product of N + 1 cones:
% 
%        C = C_0 x C_1 x .... x C_N x C_{N+1}.
% 
%     The first cone C_0 is the nonnegative orthant of dimension ml.
%     The next N cones are second order cones of dimension mq[0], ...,
%     mq[N-1].  The second order cone of dimension m is defined as
% 
%         { (u0, u1) in R x R^{m-1} | u0 >= ||u1||_2 }.
% 
%     Input arguments:
% 
%         c is a dense matrix of size (n,1).
% 
%         dims is a struct with the dimensions of the components of C.
%         It has two fields.
%         - dims.l = ml, the dimension of the nonnegative orthant C_0.
%           (ml >= 0.)
%         - dims.q = mq = [ mq[1], mq[2], ..., mq[N] ], a row vector of N
%           integers with the dimensions of the second order cones C_1, ...,
%           C_N.  (N >= 0 and mq[k] >= 1.)
%         The default value of dims is dims.l = size(G,2) and dims.q = [].
% 
%         G is a dense or sparse matrix of size (K,n), where
% 
%             K = ml + mq[1] + ... + mq[N].
% 
%         Each column of G describes a vector
% 
%             v = ( v_0, v_1, ..., v_N+1 )
% 
%         in V = R^ml x R^mq[1] x ... x R^mq[N]
%         stored as a column vector
% 
%             [ v_0; v_1; ...; v_N+1 ].
% 
%         h is a dense matrix of size (K,1), representing a vector in V,
%         in the same format as the columns of G.
% 
%         A is a dense or sparse matrix of size (p,n).  The default value
%         is [].
% 
%         b is a dense matrix of size (p,1).   The default value is [].
% 
%         It is assumed that rank(A) = p and rank([A; G]) = n.
% 
% NOTE: The solver and the text above are heavily based on the document
%
%  [1] L. Vandenberghe: "The CVXOPT linear and quadratic cone program 
%      solvers", March 20, 2010. 
%      [Online]: http://abel.ee.ucla.edu/cvxopt/documentation/coneprog.pdf
%  
%
% (c) Alexander Domahidi, IfA, ETH Zurich, 2012.

tic;

%% Parameters
MAXIT = 30;                       % maximum number of iterations
SCALING = 'Nesterov-Todd';        % primal-dual scaling method
                                  % so far only 'Nesterov-Todd' implemented
GAMMA = 0.98;                     % scaling the final step length
DOPRINTS = 1;                     % toggle printing
EPS = 1e-7;                       % regularization parameter
NITREF = 3;                     % number of iterative refinement steps

FEASTOL = 1e-6;                   % primal infeasibility tolerance
ABSTOL  = 1e-6;                   % absolute tolerance on duality gap
RELTOL  = 1e-6;                   % relative tolerance on duality gap


% EXITCODES ------------------------------------------------------------ */
CONELP_NUMERICS = 2;    % Line search gave step length 0: numerics? */
CONELP_MAXIT    = 1;    % Maximum number of iterations reached      */
CONELP_OPTIMAL  = 0;    % Problem solved to optimality              */
CONELP_PINF     = -1;   % Found certificate of primal infeasibility */
CONELP_DINF     = -2;   % Found certificate of dual infeasibility   */
CONELP_KKTZERO  = -3;   % Element of D zero during factorization    */
CONELP_OUTCONE  = -5;   % s or z got outside the cone, numerics?    */
CONELP_FATAL    = -7;   % Unknown problem in solver                 */



global CONELP_LINSOLVER_;
if(isempty(CONELP_LINSOLVER_))
    CONELP_LINSOLVER_ = 'backslash';
end
switch lower(CONELP_LINSOLVER_)
%     case 'backslash'
%         LINSOLVER = 'backslash';
%     case 'backslash2'
%         LINSOLVER = 'backslash2';
%     case 'backslash3'
%         LINSOLVER = 'backslash3'; 
    case 'ldlsparse'
        LINSOLVER = 'ldlsparse';
%     case 'ldlsparse2'
%         LINSOLVER = 'ldlsparse2';
%     case 'ldlsparse3'
%         LINSOLVER = 'ldlsparse3';
%     case 'ldlsparse4'
%         LINSOLVER = 'ldlsparse4';
%     case 'ldlsparse5'
%         LINSOLVER = 'ldlsparse5';    
%     case 'ldlsparse6'
%         LINSOLVER = 'ldlsparse6';
    
    otherwise
        error('Invalid solver method');
end


global WRITE_INTERMEDIATE_RESULTS;
WRITE_INTERMEDIATE_RESULTS = 0;


%LINSOLVER = 'backslash';         % linear solver. Choose between
                                  % 'backslash' (MATLAB)                                    
                                  % 'ldlsparse' (sparse LDL by Tim Davis)
                                  % 'conelp_ldl' (naive LDL solver by AD)

%% Input argument checking
assert(nargin >= 4,'conelp needs at least 4 arguments: conelp(c,G,h,dims)');
if    ( nargin == 4 ), A = []; b = [];
elseif( nargin == 5 ), error('Too few input arguments - define A and b for equality A*x = b');
end

% get dimensions:
% -- n: number of primal variables x
% -- m: number of conic variables s
% -- p: number of equality constraints on x
[m, n] = size(G); 
p = size(A,1);
% mtilde = m + length(dims.q);

% dimension checking
if( p > 0 )
    assert( size(b,1) == p,'b and A dimension 1 mismatch' );
    assert( size(A,2) == n,'A dimension 2 mismatch' );
end
assert( size(c,1) == n,'c dimension mismatch');
assert( size(h,1) == m,'h and G dimension 1 mismatch' );
assert( dims.l+sum(dims.q) == m,'Wrong dimension information in dims struct' );

%% 0. Init

% init info struct
info.LINSOLVER = LINSOLVER;
info.numerr = 0;
info.r0 = FEASTOL;
info.pinf = 0;
info.dinf = 0;

% need to stretch G to go with sparse representation
% Gtilde = conelp_stretch(G, dims);

% init variables
[P,x,y,s,z,tau,kap] = conelp_init(c,G,h,dims,A,b, EPS, NITREF);

% scaling
[scaling,lambda,Vreg,Vtrue,pp] = conelp_scaling(s,z,dims);
pp = [zeros(n+p,length(dims.q)); pp];

% other variables
alphaaff = 0; alpha = 0;
em = conelp_e(dims);
resx0 = max([1,norm(c,2)]); 
resy0 = max([1,norm(b,2)]); 
resz0 = max([1,norm(h,2)]);


if( WRITE_INTERMEDIATE_RESULTS )
    dumpMatrix(x, 'M_x_init.txt');
    dumpMatrix(y, 'M_y_init.txt');
    dumpMatrix(z, 'M_z_init.txt');
    dumpMatrix(s, 'M_s_init.txt');
    dumpMatrix(s, 'P.txt');
end


%% Main interior-point loop - [1, ?7.1]
% Note: we omit the "hat" for all variables for brevity
for nIt = 0:MAXIT+1
    
    
    %% 1a. Evaluate residuals, gap and stopping criteria.  
    % [ rx ]   [   0   ]   [  0   A'  G' c ] [  x  ]
    % [ ry ]   [   0   ]   [ -A   0   0  b ] [  y  ]
    % [ rz ] = [   s   ] - [ -G   0   0  h ] [  z  ]
    % [ rt ]   [ kappa ]   [ -c' -b' -h' 0 ] [ tau ]    
    if( p > 0 )
        hrx = -A'*y - G'*z;  
        hry = A*x;
    else
        hrx = -G'*z;  
        hry = [];
    end
    hrz = s + G*x;
    
    rx = hrx - c.*tau;     hresx = norm(hrx,2);     cx = c'*x;
    ry = hry - b.*tau;     hresy = norm(hry,2);     hz = h'*z;
    rz = hrz - h.*tau;     hresz = norm(hrz,2);     sz = s'*z;
    
%     fprintf('norm(rx) = %6.4e\n', norm(rx));
%     fprintf('norm(ry) = %6.4e\n', norm(ry));
%     fprintf('norm(rz) = %6.4e\n', norm(rz));
    
    if( p > 0 ), by = b'*y; else by = 0; end  % only in presense of eq. constr.
    rt = kap + cx + by + hz;
    % 
    % and  mu = (s'*z + kappa*tau) / (m+1)     
    info.mu = (sz + kap*tau)/(m+1);    
       
    %% 1b. Statistics.
    info.iter = nIt;                                  % iteration count
    info.kapovert = kap/tau;                          % ratio kappa / tau
    info.step_aff = alphaaff;                         % affine step length
    info.step = alpha;                                % step length
    info.gap = sz;                                    % duality gap
    info.pcost = cx/tau;                              % primal objective
    info.dcost = -(hz + by)/tau;                      % dual objective
    
    % relative duality gap
    if    ( info.pcost < 0 ), info.relgap = info.gap / (-info.pcost);  
    elseif( info.dcost > 0 ), info.relgap = info.gap / info.dcost;
    else                      info.relgap = NaN;
    end
      
    info.pres = max([norm(ry,2)/resy0, norm(rz,2)/resz0])/tau; % primal residuals
    info.dres = norm(rx,2)/resx0/tau;                          % dual residuals
    
    % primal infeasibility measure
    if( hz+by < 0 ), info.pinfres = hresx/resx0/(-hz-by)*tau; 
    else             info.pinfres = NaN; end               
    
    % dual infeasibility measure
    if( cx < 0 ),    info.dinfres = max([hresy/resy0, hresz/resz0])/(-cx)*tau; 
    else             info.dinfres = NaN; end
    
    %% 1c. Printing    
    if( DOPRINTS ), conelp_print(info); end
    
    %% 1d. Check termination critera and exit if necessary.
    
    % Optimal?
    if( info.pres <= FEASTOL && info.dres <= FEASTOL && ...
        (info.gap <= ABSTOL || info.relgap <= RELTOL) )                        
        if( DOPRINTS ), fprintf('Optimal solution found.\n\n'); end  
        info.exitflag = CONELP_OPTIMAL;
        break;
            
    % Primal infeasible?
    elseif( ~isnan(info.pinfres) && info.pinfres <= FEASTOL )
        if( DOPRINTS ), fprintf('Certificate of primal infeasibility found.\n\n'); end
        info.pinf = 1;
        info.dinf = 0;
        info.exitflag = CONELP_PINF;
        break;
        
    % Dual infeasible?
    elseif( ~isnan(info.dinfres) && info.dinfres <= FEASTOL )
        if( DOPRINTS ), fprintf('Certificate of dual infeasibility found.\n\n'); end
        info.pinf = 0;
        info.dinf = 1;    
        info.exitflag = CONELP_DINF;
        break;
    
    % MAXIT reached?
    elseif( nIt == MAXIT )
        if( DOPRINTS ), fprintf('Maximum number of iterations reached, exiting.\n\n'); end
        info.numerr = 1;       
        info.exitflag = CONELP_MAXIT;
        break;
    end        
    
    %% 2. Affine search direction.
    
    % build & factor KKT matrix
    K = conelp_KKTmatrix(A, G, Vreg, EPS);
         
% fprintf('cond(K) = %4.2e\n', condest(K));

    [~,DD] = ldlsparse(K,1:size(K,1));
    S = sign(full(diag(DD)));
    [L, D] = conelp_factor(K, P);
    assert( all( ~isnan(L(:)) ), 'Factorization returned NaN');
    assert( all( ~isnan(D(:)) ), 'Factorization returned NaN');
    
    if( WRITE_INTERMEDIATE_RESULTS )
        dumpMatrix(full(L), 'M_K.txt');
        dumpMatrix(P'-1, 'M_P.txt');
    end
    
%     break;
    
    % first solve for x1 y1 z1
    [x1,y1,z1] = conelp_solve(L,D,P, -c,b,h, A,Gtilde,Vtrue, dims, NITREF);
    assert( all( ~isnan(x1) ), 'Linear solver returned NaN');
    assert( all( ~isnan(y1) ), 'Linear solver returned NaN');
    assert( all( ~isnan(z1) ), 'Linear solver returned NaN');
    
%     rowprint(x1,sprintf('x1_%02d',nIt));
%     rowprint(y1,sprintf('y1_%02d',nIt));
%     rowprint(z1,sprintf('z1_%02d',nIt));
    
%     break;
    
    % second solve for x2 y2 z2
    bx = rx;  by = ry;  bz = -rz + s; dt = rt - kap;  bkap = kap*tau;            
    [x2,y2,z2] = conelp_solve(L,D,P, bx,by,bz, A,Gtilde,Vtrue, dims, NITREF);
    if( p > 0 ), by1 = b'*y1; else by1 = 0; end    
    if( p > 0 ), by2 = b'*y2; else by2 = 0; end  
    dtau_denom = kap/tau - (c'*x1 + by1 + h'*z1);
    dtauaff = (dt + c'*x2 + by2 + h'*z2) / dtau_denom;
    dzaff = z2 + dtauaff*z1;    
    W_times_dzaff = conelp_timesW(scaling,dzaff,dims); % = W*dzaff
    
    dsaff = -conelp_timesWsquare(scaling, dzaff, dims) - s; 
    % W \ dsaff = -W*dzaff - lambda
    % dsaff as such not needed, line search is on scaled variables
    dsaff_by_W =  -conelp_timesW(scaling, dzaff, dims) - lambda;
    
    dkapaff = -(bkap + kap*dtauaff)/tau;
        
    %% 3. Step length computation and centering parameter.    
    alphaaff = conelp_stepsize(lambda,dsaff_by_W,W_times_dzaff,dims,tau,dtauaff,kap,dkapaff);
%     fprintf('Affine step length: %10.8f\n',alphaaff);
    %     alphaaff = conelp_linesearch(s,z,tau,kap,dsaff,dzaff,dtauaff,dkapaff,dims,lambda);
    muaff =  ( em'*abs(conelp_kringel( s + alphaaff*dsaff, z + alphaaff*dzaff, dims)) + (tau+alphaaff*dtauaff)*(kap+alphaaff*dkapaff));% / (length(s)+1);
%     fprintf('Muaff = %10.8f\n',muaff);
    mu = ( em'*abs(conelp_kringel(s,z,dims)) + kap*tau);% / (length(s)+1);
%     fprintf('Mu = %10.8f\n',mu);
    sigma = (muaff/mu)^3;
%     sigma = 1.3*(1-alphaaff)^3;
    if(sigma < 0 )
        error('Centering parameter < 0');
    end
    if( sigma > 1 ), sigma = 1; end
%     fprintf('Centering parameter: %10.8f\n',sigma);

    
    %% 4. Combined search direction.            
    bs = conelp_kringel(lambda,lambda,dims) - sigma*info.mu*em + conelp_kringel(dsaff_by_W,W_times_dzaff,dims);     
    bkap = kap*tau - sigma*info.mu + dkapaff*dtauaff;
    lambda_raute_bs = conelp_raute(lambda,bs,dims);    
    W_times_lambda_raute_bs = conelp_timesW(scaling,lambda_raute_bs,dims);
    [x2, y2, z2] = conelp_solve(L,D,P, (1-sigma)*rx,(1-sigma)*ry,-(1-sigma)*rz + W_times_lambda_raute_bs, A,Gtilde,Vtrue, dims, NITREF); 
    if( p > 0 ), by2 = b'*y2; else by2 = 0; end
    dtau = ((1-sigma)*rt - bkap/tau + c'*x2 + by2 + h'*z2) / dtau_denom;
    dx = x2 + dtau*x1;     dy = y2 + dtau*y1;       dz = z2 + dtau*z1;
    ds_by_W = -(lambda_raute_bs + conelp_timesW(scaling,dz,dims));
    ds = conelp_timesW(scaling, ds_by_W, dims);
    dkap = -(bkap + kap*dtau)/tau;    
    
    %% 5. Line search for combined search direction.    
    W_times_dz = conelp_timesW(scaling,dz,dims); % = W*dz
    alpha = conelp_stepsize(lambda,ds_by_W,W_times_dz,dims,tau,dtau,kap,dkap)*GAMMA;
%     fprintf('Combined step length: %10.8f\n',alpha);
%     alpha = conelp_linesearch(s,z,tau,kap,ds,dz,dtau,dkap,dims,lambda)*GAMMA;          
    
    %% 6. Update variables and scaling.    
    x = x + alpha*dx; y = y + alpha*dy; s = s + alpha*ds; z = z + alpha*dz;
    kap = kap + alpha*dkap;     tau = tau + alpha*dtau;
    assert( tau > 0, 'tau <= 0, exiting.');
    assert( kap > 0, 'kappa <= 0, exiting');
    [scaling,lambda,Vreg,Vtrue,Signs] = conelp_scaling(s,z,dims);    
end

%% scale variables back
x = x ./ tau; y = y ./ tau; s = s ./ tau; z = z ./ tau;

info.runtime = toc;