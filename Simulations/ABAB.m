% generate subsymbol

subsymbolLength = 512;
subsymbol = zeros(1,subsymbolLength);

carrierCount = 25;
startFrequency = 197;
for f=startFrequency:startFrequency+carrierCount-1
     subsymbol = subsymbol + cos(2 * pi * f * (0:1/subsymbolLength:1-1/subsymbolLength) + 2*pi*rand);
end

% generate symbol
symbol = subsymbol;
symbol(subsymbolLength+1:subsymbolLength+subsymbolLength) = fliplr(subsymbol);
symbol(2*subsymbolLength+1:4*subsymbolLength) = symbol;

% generate signal
signalLength = 16000;
signal = zeros(1,signalLength);
signal(7000:7000+4*subsymbolLength-1) = symbol;
% add noise to signal
 signal = signal + 20*(rand(1,signalLength)-0.5);

% normalize signal
signal = signal / max(signal);


% detect signal
correlation = zeros(1,signalLength);
for signalStart=1:signalLength-1
    normalization = 0;
    for i=0:2*subsymbolLength-1
        if (signalStart + 4*subsymbolLength - i <= signalLength)
            correlation(signalStart) = correlation(signalStart) + signal(signalStart+i) * signal(signalStart + 4*subsymbolLength - i - 1);
            normalization = normalization + signal(signalStart + i);
        end
    end
     %correlation(signalStart) = correlation(signalStart)/normalization;
end

correlation =correlation/max(correlation);
figure;
plot(signal);hold all;plot(correlation);hold off;figure(gcf);