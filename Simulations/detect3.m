% Load raw data.
rawData = importdata('rawData.txt');
% rawData = rawData(40000:90000-1);
rawDataCount = size(rawData,1);

% Perform fft.
rawDataFFT = fft(rawData);

% Compute the ultra sounds frequencies used by AirNFC.
minimumOscillationCount = 789;
carrierCount = 100;
oscillationPeriod = 2048;
minimumFrequency = ceil(minimumOscillationCount * rawDataCount / oscillationPeriod);
maximumFrequency = floor((minimumOscillationCount+carrierCount-1) * rawDataCount / oscillationPeriod);

% Let only interesting frequencies pass.
rawDataFFT(1:minimumFrequency) = 0;
rawDataFFT(1+maximumFrequency+1:size(rawDataFFT,1)) = 0;

% Perform inverse FFT.
filteredData = ifft(rawDataFFT, 'symmetric');

% Compute correlation
symbolSize = 128;
correlations = zeros(size(rawData));
maxCorrelation = 0;
synchronizationSymbol = synchronizationSymbol();
synchronizationSymbol = synchronizationSymbol(1:length(synchronizationSymbol)/2);
synchronizationSymbol = synchronizationSymbol / norm(synchronizationSymbol);
for signalStart=1:rawDataCount-symbolSize+1
    signal = filteredData(signalStart:signalStart+symbolSize-1);
    signal = signal / norm(signal);
    % Compute the scalar product of the synchronization symbol and the
    % the current signal starting at `signalStart`.
    correlations(signalStart) = synchronizationSymbol' * signal;
    if correlations(signalStart) > maxCorrelation
        maxCorrelation = correlations(signalStart)
        signalStart
    end
end

figure;
plot(correlations);hold all;plot(filteredData);hold off;figure(gcf);