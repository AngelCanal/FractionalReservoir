function dydt = meanfield_EI_STD_DDE_rhs(xx, par)
% meanfield_EI_STD_DDE_rhs
% RHS for reduced E-I-adaptation-STD model with one inhibitory delay.
%
% DDE-BIFTOOL sys_rhs signature:
%   dydt = sys_rhs(xx, par)
% where xx is (n x (m+1)) with m delays; xx(:,1) current, xx(:,j+1) delayed.
%
% State y = [E; I; a; b]
%
% Parameters par (see meanfield_EI_STD_DDE.m):
%   [wEE,wEI,wIE,wII,IextE,IextI,tauE,tauI,tau_a,c_a,tau_rec,tau_rel,tau_delay,gain,bias]

    y = xx(:, 1);
    if size(xx, 2) >= 2
        y_tau = xx(:, 2);
    else
        y_tau = y;
    end

    E = y(1);
    I = y(2);
    a = y(3);
    b = y(4);

    I_del = y_tau(2);

    wEE = par(1); wEI = par(2); wIE = par(3); wII = par(4);
    IextE = par(5); IextI = par(6);
    tauE = par(7); tauI = par(8);
    tau_a = par(9); c_a = par(10);
    tau_rec = par(11); tau_rel = par(12);
    gain = par(14); bias = par(15);

    % Effective inputs
    inE = wEE * (b * E) - wEI * I_del + IextE - c_a * a;
    inI = wIE * (b * E) - wII * I + IextI;

    phiE = phi(inE, gain, bias);
    phiI = phi(inI, gain, bias);

    dE = (-E + phiE) / tauE;
    dI = (-I + phiI) / tauI;
    da = (-a + E) / tau_a;

    % STD on E presynaptic output
    db = (1 - b) / tau_rec - (b * max(E, 0)) / tau_rel;

    dydt = [dE; dI; da; db];
end

function r = phi(x, gain, bias)
    r = 0.5 * (tanh(gain * (x - bias)) + 1.0);
end

