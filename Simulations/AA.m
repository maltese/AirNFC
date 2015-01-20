% generate signal

subsymbolLength = 1024;
subsymbol = zeros(1,subsymbolLength);

carrierCount = 50;
startFrequency = 394;
for f=startFrequency:startFrequency+carrierCount-1
    subsymbol = subsymbol + cos(2 * pi * f * (0:1/subsymbolLength:1-1/subsymbolLength) + 2*pi*rand);
end

symbol = subsymbol;
symbol(subsymbolLength+1:subsymbolLength+subsymbolLength) = subsymbol;

signalLength = 8192;
signal = zeros(1,signalLength);
signal(3072:3072+2*subsymbolLength-1) = symbol;
% add noise to signal
signal = signal + 1*rand(1,signalLength);

% normalize signal
signal = signal / max(signal);

% detect signal

correlation = zeros(1,signalLength);
for signalStart=1:signalLength-1
    normalization = 0;
   for i=signalStart:signalStart+subsymbolLength-1
       if (i + subsymbolLength <= signalLength)
            correlation(signalStart) = correlation(signalStart) + signal(i) * signal(i + subsymbolLength);
            normalization = normalization + signal(i + subsymbolLength)^2;
       end
   end
   correlation(signalStart) = correlation(signalStart)^2 / normalization^2;
end

plot(signal);hold all;plot(correlation);hold off;figure(gcf);