% generate signal

subsymbolLength = 1024;
subsymbol = zeros(1,subsymbolLength);

carrierCount = 50;
startFrequency = 394;
for f=startFrequency:startFrequency+carrierCount-1
     subsymbol = subsymbol + cos(2 * pi * f * (0:1/subsymbolLength:1-1/subsymbolLength) + 2*pi*rand);
end

symbol = subsymbol;
symbol(subsymbolLength+1:subsymbolLength+subsymbolLength) = fliplr(subsymbol);

signalLength = 16000;
signal = zeros(1,signalLength);
signal(7000:7000+2*subsymbolLength-1) = symbol;
% add noise to signal
signal = signal + 20*(rand(1,signalLength)-0.5);

% normalize signal
signal = signal / max(signal);

% detect signal

correlation = zeros(1,signalLength);
for signalStart=1:signalLength-1
    normalization = 0;
    for i=0:subsymbolLength-1
        if (signalStart + 2*subsymbolLength - i < signalLength)
            correlation(signalStart) = correlation(signalStart) + signal(signalStart+i) * signal(signalStart + 2*subsymbolLength - i -1);
            %normalization = normalization + signal(signalStart+i)^2;
        end
    end
    %correlation(signalStart) = correlation(signalStart)^2;
end

correlation =correlation/max(correlation);
figure;
plot(signal);hold all;plot(correlation);hold off;figure(gcf);