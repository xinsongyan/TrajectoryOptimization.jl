using Test
# Test constraint stuff
n,m = 3,2
cE(x,u) = [2x[1:2]+u;
          x'x + 5]
pE = 3
cE(x) = [cos(x[1]) + x[2]*x[3]; x[1]*x[2]^2]
pE_N = 2
cI(x,u) = [x[3]-x[2]; u[1]*x[1]]
pI = 2
pI_N = 0

model, obj = Dynamics.dubinscar
obj.tf = 3
count_inplace_output(cI,n,m)
obj_con = ConstrainedObjective(obj,cE=cE,cI=cI)
@test obj_con.p == pE + pI
@test obj_con.pI == pI
@test obj_con.pI_N == pI_N
@test obj_con.p_N == n + pE_N + pI_N

N = 5
solver = Solver(model, obj, N=N)
@test solver.state.constrained == true
@test get_num_constraints(solver) == (5,2,3)
@test original_constraint_inds(solver) == trues(5)
@test get_constraint_labels(solver) == ["custom inequality", "custom inequality", "custom equality", "custom equality", "custom equality"]

# Add state and control bounds
obj_con = update_objective(obj_con, u_min=[-10,-Inf], u_max=10, x_min=[-Inf,-10,-Inf], x_max=[10,12,10])
pI_bnd = 1 + m + 1 + n
@test obj_con.pI == pI + pI_bnd
@test obj_con.p == pI + pI_bnd + pE
p = obj_con.p
pI = obj_con.pI
pE = p-pI

N = 5
solver = Solver(model, obj_con, N=N)
@test solver.state.constrained == true
@test get_num_constraints(solver) == (5+pI_bnd,2+pI_bnd,3)
@test original_constraint_inds(solver) == trues(5+pI_bnd)
@test get_constraint_labels(solver) == ["control (upper bound)", "control (upper bound)", "control (lower bound)", "state (upper bound)", "state (upper bound)", "state (upper bound)", "state (lower bound)",
    "custom inequality", "custom inequality", "custom equality", "custom equality", "custom equality"]

# Infeasible controls
solver_inf = Solver(model, obj_con, N=N)
solver_inf.opts.infeasible = true
@test solver_inf.opts.constrained == true
@test get_num_constraints(solver_inf) == (p+n,pI,pE+n)
@test original_constraint_inds(solver_inf) == [trues(p); falses(n)]
@test get_constraint_labels(solver_inf) == ["control (upper bound)", "control (upper bound)", "control (lower bound)", "state (upper bound)", "state (upper bound)", "state (upper bound)", "state (lower bound)",
    "custom inequality", "custom inequality", "custom equality", "custom equality", "custom equality",
    "* infeasible control","* infeasible control","* infeasible control"]

# Minimum time
obj_mintime = update_objective(obj_con, tf=:min)
solver_min = Solver(model, obj_mintime, N=N)
@test solver_min.opts.constrained == true
@test get_num_constraints(solver_min) == (p+3,pI+2,pE+1)
@test original_constraint_inds(solver_min) == [true; true; false; true; false; trues(4); trues(5); false]
@test get_constraint_labels(solver_min) == ["control (upper bound)", "control (upper bound)", "* √dt (upper bound)", "control (lower bound)", "* √dt (lower bound)", "state (upper bound)", "state (upper bound)", "state (upper bound)", "state (lower bound)",
    "custom inequality", "custom inequality", "custom equality", "custom equality", "custom equality",
    "* √dt (equality)"]

# Minimum time and infeasible
obj_mintime = update_objective(obj_con, tf=:min)
solver_min = Solver(model, obj_mintime, N=N)
solver_min.opts.infeasible = true
@test solver_min.opts.constrained == true
@test get_num_constraints(solver_min) == (p+3+n,pI+2,pE+1+n)
@test original_constraint_inds(solver_min) == [true; true; false; true; false; trues(4); trues(5); falses(4)]
@test get_constraint_labels(solver_min) == ["control (upper bound)", "control (upper bound)", "* √dt (upper bound)", "control (lower bound)", "* √dt (lower bound)", "state (upper bound)", "state (upper bound)", "state (upper bound)", "state (lower bound)",
    "custom inequality", "custom inequality", "custom equality", "custom equality", "custom equality",
    "* infeasible control","* infeasible control","* infeasible control","* √dt (equality)"]
get_constraint_labels(solver_min)



####################
# NEW CONSTRAINTS #
###################

n,m = 3,2

# Custom Equality Constraint
p1 = 3
c(v,x,u) = begin v[1]  = x[1]^2 + x[2]^2 - 5; v[2:3] =  u - ones(2,1) end
jacob_c(x,u) = [2x[1] 2x[2] 0 0 0;
                0     0     0 1 0;
                0     0     0 0 1];
v = zeros(p1)
x = [1,2,3]
u = [-5,5]
c(v,x,u)
@test v == [0,-6,4]

# Test constraint function
con = Constraint{Equality}(c,n,m,p1,:custom)
con.c(v,x,u)
@test v == [0,-6,4]

# Test constraint jacobian
A = zeros(p1,n)
B = zeros(p1,m)
C = zeros(p1,n+m)
con.∇c(A,B,v,x,u);
@test A == jacob_c(x,u)[:,1:n]
@test B == jacob_c(x,u)[:,n+1:end]

# Joint jacobian function
con.∇c(C,v,[x;u])
@test C == jacob_c(x,u)


# Custom inequality constraint
p2 = 2
c2(v,x,u) = begin v[1] = sin(x[1]); v[2] = sin(x[3]) end
∇c2(A,B,v,x,u) = begin A[1,1] = cos(x[1]); A[2,3] = cos(x[3]); c2(v,x,u) end
con2 = Constraint{Inequality}(c2,∇c2,p2,:ineq)

# Bound constraint
x_max = [5,5,Inf]
x_min = [-10,-5,0]
u_max = 0
u_min = -10
p3 = 2(n+m)
bnd = bound_constraint(n,m,x_max=x_max,x_min=x_min,u_min=u_min,u_max=u_max)
v = zeros(p3)
bnd.c(v,x,u)
@test v == [-4,-3,-Inf,-5,5,-11,-7,-3,-5,-15]
A = zeros(p3,n)
B = zeros(p3,m)
C = zeros(p3,n+m)
bnd.∇c(A,B,v,x,u)
@test A == [Diagonal(I,n); zeros(m,n); -Diagonal(I,n); zeros(m,n)]
@test B == [zeros(n,m); Diagonal(I,m); zeros(n,m); -Diagonal(I,m)]

# Trimmed bound constraint
bnd = bound_constraint(n,m,x_max=x_max,x_min=x_min,u_min=u_min,u_max=u_max,trim=true)
p3 = 2(n+m)-1
v = zeros(p3)
bnd.c(v,x,u)
@test v == [-4,-3,-5,5,-11,-7,-3,-5,-15]

# Create Constraint Set
C = [con,con2,bnd]
@test C isa ConstraintSet
@test C isa StageConstraintSet
@test !(C isa TerminalConstraintSet)

@test findall(C,Inequality) == [false,true,true]
@test split(C) == ([con2,bnd],[con,])
@test count_constraints(C) == (p2+p3,p1)
@test inequalities(C) == [con2,bnd]
@test equalities(C) == [con,]
@test bounds(C) == [bnd,]
@test labels(C) == [:custom,:ineq,:bound]

c_part = create_partition(C)
cs2 = BlockArray(C)
calculate!(cs2,C,x,u)

obj = LQRObjective(Diagonal(I,n),Diagonal(I,m),Diagonal(I,n),2.,zeros(n),ones(n))
obj = ConstrainedObjective(obj,u_max=u_max,u_min=u_min,x_max=x_max,x_min=x_min,cI=c2,cE=c)
cfun, = generate_constraint_functions(obj)
cs = zeros(obj.p)
cfun(cs,x,u)

# Test sum since they're ordered differently
@test sum(cs) == sum(cs2)

@btime calculate!(cs2,C,x,u)
@btime cfun(cs,x,u)


# Terminal Constraint
cterm(v,x) = begin v[1] = x[1] - 5; v[2] = x[1]*x[2] end
∇cterm(x) = [1 0 0; x[2] x[1] 0]
∇cterm(A,x) = copyto!(A,∇cterm(x))
p_N = 2
v = zeros(p_N)
cterm(v,x)
con_term = TerminalConstraint{Equality}(cterm,∇cterm,p_N,:terminal)
v2 = zeros(p_N)
con_term.c(v2,x)
@test v == v2
A = zeros(p_N,n)
con_term.∇c(A,x) == ∇cterm(x)

C_term = [con_term,]
C2 = [con,con2,bnd,con_term]
@test C2 isa ConstraintSet
@test C_term isa TerminalConstraintSet

@test terminal(C2) == C_term
@test terminal(C_term) == C_term
@test stage(C2) == C
@test isempty(terminal(C))
@test isempty(stage(C_term))
@test count_constraints(C_term) == (0,p_N)
@test count_constraints(C2) == (p2+p3,p1+p_N)
@test split(C2) == ([con2,bnd],[con,con_term])
@test split(C2) == (inequalities(C2),equalities(C2))
@test bounds(C2) == [bnd,]
@test labels(C2) == [:custom,:ineq,:bound,:terminal]
terminal(C2)
Vector{Constraint}(stage(C2)) isa StageConstraintSet

v_stage = BlockArray(stage(C2))
v_term = BlockArray(terminal(C2))
v_stage2 = BlockArray(stage(C2))
v_term2 = BlockArray(terminal(C2))
calculate!(v_stage,C,x,u)
calculate!(v_term,C_term,x)
calculate!(v_stage2,C2,x,u)
calculate!(v_term2,C2,x)
@test v_stage == v_stage2
@test v_term == v_term2
