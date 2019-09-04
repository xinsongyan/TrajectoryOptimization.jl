include(joinpath(pwd(),"dynamics/quaternions.jl"))

num_lift = 3
mass_load = 0.35
mass_lift = 0.85

quad_params = (m=mass_lift,
             J=SMatrix{3,3}(Diagonal([0.0023, 0.0023, 0.004])),
             Jinv=SMatrix{3,3}(Diagonal(1.0./[0.0023, 0.0023, 0.004])),
             gravity=SVector(0,0,-9.81),
             motor_dist=0.175,
             kf=1.0,
             km=0.0245)

function gen_load_model_initial(xload0,xlift0)
    function double_integrator_3D_dynamics_load!(ẋ,x,u) where T
        Δx1 = (xlift0[1][1:3] - xload0[1:3])
        Δx2 = (xlift0[2][1:3] - xload0[1:3])
        Δx3 = (xlift0[3][1:3] - xload0[1:3])
        u_slack1 = u[1]*Δx1/norm(Δx1)
        u_slack2 = u[2]*Δx2/norm(Δx2)
        u_slack3 = u[3]*Δx3/norm(Δx3)
        Dynamics.double_integrator_3D_dynamics!(ẋ,x,(u_slack1+u_slack2+u_slack3)/mass_load)
    end
    Model(double_integrator_3D_dynamics_load!,6,3)
end

function gen_lift_model_initial(xload0,xlift0)

        function quadrotor_lift_dynamics!(ẋ::AbstractVector,x::AbstractVector,u::AbstractVector,params)
            q = normalize(Quaternion(view(x,4:7)))
            v = view(x,8:10)
            omega = view(x,11:13)

            # Parameters
            m = params[:m] # mass
            J = params[:J] # inertia matrix
            Jinv = params[:Jinv] # inverted inertia matrix
            g = params[:gravity] # gravity
            L = params[:motor_dist] # distance between motors

            w1 = u[1]
            w2 = u[2]
            w3 = u[3]
            w4 = u[4]

            kf = params[:kf]; # 6.11*10^-8;
            F1 = kf*w1;
            F2 = kf*w2;
            F3 = kf*w3;
            F4 = kf*w4;
            F = @SVector [0., 0., F1+F2+F3+F4] #total rotor force in body frame

            km = params[:km]
            M1 = km*w1;
            M2 = km*w2;
            M3 = km*w3;
            M4 = km*w4;
            tau = @SVector [L*(F2-F4), L*(F3-F1), (M1-M2+M3-M4)] #total rotor torque in body frame

            ẋ[1:3] = v # velocity in world frame
            ẋ[4:7] = SVector(0.5*q*Quaternion(zero(x[1]), omega...))
            Δx = xload0[1:3] - xlift0[1:3]
            dir = Δx/norm(Δx)
            ẋ[8:10] = g + (1/m)*(q*F + u[5]*dir) # acceleration in world frame
            ẋ[11:13] = Jinv*(tau - cross(omega,J*omega)) #Euler's equation: I*ω + ω x I*ω = constraint_decrease_ratio
            return tau, omega, J, Jinv
        end
        Model(quadrotor_lift_dynamics!,13,5,quad_params)
end

function gen_lift_model(X_load,N,dt)
      model = Model[]

      for k = 1:N-1
        function quadrotor_lift_dynamics!(ẋ::AbstractVector,x::AbstractVector,u::AbstractVector,params)
            q = normalize(Quaternion(view(x,4:7)))
            v = view(x,8:10)
            omega = view(x,11:13)

            # Parameters
            m = params[:m] # mass
            J = params[:J] # inertia matrix
            Jinv = params[:Jinv] # inverted inertia matrix
            g = params[:gravity] # gravity
            L = params[:motor_dist] # distance between motors

            w1 = u[1]
            w2 = u[2]
            w3 = u[3]
            w4 = u[4]

            kf = params[:kf]; # 6.11*10^-8;
            F1 = kf*w1;
            F2 = kf*w2;
            F3 = kf*w3;
            F4 = kf*w4;
            F = @SVector [0., 0., F1+F2+F3+F4] #total rotor force in body frame

            km = params[:km]
            M1 = km*w1;
            M2 = km*w2;
            M3 = km*w3;
            M4 = km*w4;
            tau = @SVector [L*(F2-F4), L*(F3-F1), (M1-M2+M3-M4)] #total rotor torque in body frame

            ẋ[1:3] = v # velocity in world frame
            ẋ[4:7] = SVector(0.5*q*Quaternion(zero(x[1]), omega...))
            Δx = X_load[k][1:3] - x[1:3]
            dir = Δx/norm(Δx)
            ẋ[8:10] = g + (1/m)*(q*F + u[5]*dir) # acceleration in world frame
            ẋ[11:13] = Jinv*(tau - cross(omega,J*omega)) #Euler's equation: I*ω + ω x I*ω = constraint_decrease_ratio
            return tau, omega, J, Jinv
        end
        push!(model,midpoint(Model(quadrotor_lift_dynamics!,13,5,quad_params),dt))
    end
    model
end

function gen_load_model(X_lift,N,dt)
      model = Model[]
      for k = 1:N-1
          function double_integrator_3D_dynamics_load!(ẋ,x,u)
              Δx1 = X_lift[1][k][1:3] - x[1:3]
              Δx2 = X_lift[2][k][1:3] - x[1:3]
              Δx3 = X_lift[3][k][1:3] - x[1:3]

              u_slack1 = u[1]*Δx1/norm(Δx1)
              u_slack2 = u[2]*Δx2/norm(Δx2)
              u_slack3 = u[3]*Δx3/norm(Δx3)
              Dynamics.double_integrator_3D_dynamics!(ẋ,x,(u_slack1+u_slack2+u_slack3)/mass_load)
          end
        push!(model,midpoint(Model(double_integrator_3D_dynamics_load!,6,3),dt))
    end
    model
end
