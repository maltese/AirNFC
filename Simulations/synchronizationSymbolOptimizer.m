% Define symbol length.
symbolLength = 256;

% Compute minimum and maximum frequencies.
minimumFrequency = ceil(789*symbolLength/2/2048);
maximumFrequency = floor((789+99)*symbolLength/2/2048);
% (6 carrier frequencies in total).

bestPAPR = 10000;
while true
    % Generate random phases.
    phases = rand(6,1)*2*pi;
    
%     Optimal Phases found so far:
%     phases = [2.437141070138417
%         1.379861523905170
%         6.048383864459403
%         3.223180788132005
%         4.936236699655129
%         5.878707885536211]; % PAPR = 1.920576579000864
    
    % Compute subsymbol.
    subsymbol = zeros(symbolLength/2,1);
    for f=minimumFrequency:maximumFrequency
        subsymbol = subsymbol + cos(2*pi*f*(0:1:symbolLength/2-1)/(symbolLength/2) + phases(f-minimumFrequency+1))';
    end
    
    % Assemble main symbol.
    symbol = [subsymbol; flipud(subsymbol)];
        
    % Perform FFT on symbol.
    symbolFFT = fft(symbol);
        
    % Filter main symbol FFT to let only allowed frequencies pass.
    symbolFFT(1:2*minimumFrequency) = 0;
    symbolFFT(2*maximumFrequency+2:size(symbolFFT)) = 0;
        
    % Perform IFFT
    symbol = ifft(symbolFFT, 'symmetric');
                
    % Compute symbol PAPR
    papr=max(symbol)^2/rms(symbol)^2;
    if papr<bestPAPR
        bestPAPR = papr
        bestPhases = phases
    end
end