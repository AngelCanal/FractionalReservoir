function mf = meanfield_EI_STD_DDE(options)
% meanfield_EI_STD_DDE
% Reduced E-I mean-field model with adaptation and short-term depression (STD)
% and a single inhibitory delay, suitable for bifurcation-like analysis.
%
% State:
%   y = [E; I; a; b]
% where
%   E, I : population activities (rates)
%   a    : adaptation (low-pass of E)
%   b    : depression variable on E presynaptic output (0..1)
%
% DDE (delay on inhibitory feedback into E):
%   I_del = I(t - tau_delay)
%
% Returns:
%   mf struct with fields:
%     .par        parameter vector
%     .par_names  names
%     .lags       vector of delays (seconds)
%     .rhs        function handle compatible with DDE-BIFTOOL sys_rhs
%     .rhs_dde23  function handle for dde23: f(t,y,Z)
%
% Note: This is a modelling scaffold; parameterisation from a full reservoir
% should be done in scripts (e.g., by matching mean(W_EE), etc.).

    if nargin < 1 || isempty(options)
        options = struct();
    end

    % Parameters (defaults chosen for qualitative behaviour)
    % Connectivity
    wEE = getFieldOrDefault(options, 'wEE', 10);
    wEI = getFieldOrDefault(options, 'wEI', 12);
    wIE = getFieldOrDefault(options, 'wIE', 10);
    wII = getFieldOrDefault(options, 'wII', 2);

    % External drive
    IextE = getFieldOrDefault(options, 'IextE', 0.5);
    IextI = getFieldOrDefault(options, 'IextI', 0.5);

    % Time constants
    tauE = getFieldOrDefault(options, 'tauE', 1.0);
    tauI = getFieldOrDefault(options, 'tauI', 1.0);
    tau_a = getFieldOrDefault(options, 'tau_a', 10.0);
    c_a = getFieldOrDefault(options, 'c_a', 1.0);

    % STD parameters
    tau_rec = getFieldOrDefault(options, 'tau_rec', 10.0);
    tau_rel = getFieldOrDefault(options, 'tau_rel', 1.0);

    % Delay
    tau_delay = getFieldOrDefault(options, 'tau_delay', 0.05);

    % Nonlinearity (tanh with gain/bias)
    gain = getFieldOrDefault(options, 'gain', 1.5);
    bias = getFieldOrDefault(options, 'bias', 0.0);

    par = [wEE,wEI,wIE,wII,IextE,IextI,tauE,tauI,tau_a,c_a,tau_rec,tau_rel,tau_delay,gain,bias];
    par_names = {'wEE','wEI','wIE','wII','IextE','IextI','tauE','tauI','tau_a','c_a','tau_rec','tau_rel','tau_delay','gain','bias'};

    mf = struct();
    mf.par = par;
    mf.par_names = par_names;
    mf.lags = tau_delay;
    mf.rhs = @meanfield_EI_STD_DDE_rhs;
    mf.rhs_dde23 = @(t, y, Z) rhs_dde23(t, y, Z, par);
end

function dy = rhs_dde23(~, y, Z, par)
    % dde23 interface: Z(:,1) corresponds to the single lag
    xx = [y, Z];
    dy = meanfield_EI_STD_DDE_rhs(xx, par);
end

function value = getFieldOrDefault(s, field, default_value)
    if isfield(s, field)
        value = s.(field);
    else
        value = default_value;
    end
end

