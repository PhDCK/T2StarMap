function [map S0 rmse] = t2starmap(data,TE)
% [map S0 rmse] = t2starmap(data,TE)
% Calculates T2* map from data
% Data is a either a 3D or 4D array, where the last dimension relates to
% the echo.
% TE are the echo times in seconds.
%
% S0 is the estimated magnitude at t=0.
% rmse is the root-mean-square error of the T2* map.

    sz = size(data);
    nd = ndims(data);
    map = zeros(sz(1:end-1));
    data = reshape(permute(data, [nd 1:nd-1]),sz(end),[]);
    x = TE(:);
    
    flgCalcExtra = nargout >= 2;
    if flgCalcExtra
        S0 = zeros(sz(1:end-1));
        rmse = zeros(sz(1:end-1));
    end
    
    for i = 1:numel(map)
        %SIij(t)=SOijexp (?t/T2ij)

        y = data(:,i);
        map(i) = -1/((sum(y)*sum(x.*y.*log(y))-sum(x.*y)*sum(y.*log(y))) / (sum(y)*sum(x.*x.*y) - sum(x.*y).^2));
        if flgCalcExtra
            S0(i) = exp((sum(x.*x.*y)*sum(y.*log(y))-sum(x.*y)*sum(x.*y.*log(y))) / (sum(y)*sum(x.*x.*y) - sum(x.*y).^2));
            rmse(i) = sqrt(mean((S0(i).*exp(-x./map(i))./max(y)-y./max(y)).^2));
        end
    end
