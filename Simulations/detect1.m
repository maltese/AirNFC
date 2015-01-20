% Load raw data.
rawData = importdata('data.txt');
rawData = rawData(40000:90000-1);
rawDataCount = size(rawData,1);

% Perform fft.
rawDataFFT = fft(rawData);

% Compute the ultra sounds frequencies used by AirNFC.
minimumOscillationCount = 789;
carrierCount = 100;
oscillationPeriod = 2048;
minimumFrequency = floor(minimumOscillationCount * rawDataCount / oscillationPeriod);
maximumFrequency = ceil((minimumOscillationCount+carrierCount-1) * rawDataCount / oscillationPeriod);

% Let only interesting frequencies pass.
rawDataFFT(2:minimumFrequency) = 0;
rawDataFFT(maximumFrequency+2:size(rawDataFFT,1)) = 0;

% Perform inverse FFT.
filteredData = ifft(rawDataFFT, 'symmetric');

% Compute correlation
symbolSize = 256;
subsymbolSize = symbolSize / 2;
correlations = zeros(size(rawData));
for signalStart=1:rawDataCount-symbolSize+1
    correlation = 0;
    for i=0:subsymbolSize-1
        correlation = correlation + filteredData(signalStart+i) * filteredData(signalStart+symbolSize-1-i);
    end
    correlations(signalStart) = correlation;
end

plot(correlations);hold all;plot(filteredData);hold off;figure(gcf);