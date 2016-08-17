%{
----------------------------------------------------------------------------

This file is part of the Sanworks Pulse Pal repository
Copyright (C) 2016 Sanworks LLC, Sound Beach, New York, USA

----------------------------------------------------------------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed  WITHOUT ANY WARRANTY and without even the 
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
%}

function ConfirmBit = SendCustomPulseTrain(TrainID, PulseTimes, Voltages)
global PulsePalSystem

if length(PulseTimes) ~= length(Voltages)
    error('There must be one voltage value (0-255) for every timestamp');
end

nPulses = length(PulseTimes);
if PulsePalSystem.FirmwareVersion > 19
    if nPulses > 5000
        error('Error: Pulse Pal 2 can only store 5000 pulses per custom pulse train.');
    end
else
    if nPulses > 1000
        error('Error: Pulse Pal 1.X can only store 1000 pulses per custom pulse train.');
    end
end

% Sanity-check PulseTimes and voltages

if sum(sum(rem(round(PulseTimes*1000000), PulsePalSystem.MinPulseDuration))) > 0
    error(['Non-zero time values for Pulse Pal must be multiples of ' num2str(PulsePalSystem.MinPulseDuration) ' microseconds.']);
end

CandidateTimes = uint32(PulseTimes*PulsePalSystem.CycleFrequency);
CandidateVoltages = Voltages;
if (sum(CandidateTimes < 0) > 0)
    error('Error: Custom pulse times must be positive');
end
if ~IsTimeSequence(CandidateTimes)
    error('Error: Custom pulse times must always increase');
end
if (CandidateTimes(end) > (3600*PulsePalSystem.CycleFrequency))
    0; error('Error: Custom pulse times must be < 3600 s');
end
if (sum(abs(CandidateVoltages) > 10) > 0)
    error('Error: Custom voltage range = -10V to +10V');
end
if (length(CandidateVoltages) ~= length(CandidateTimes))
    error('Error: There must be a voltage for every timestamp');
end
if (length(unique(CandidateTimes)) ~= length(CandidateTimes))
    error('Error: Duplicate custom pulse times detected');
end
TimeOutput = CandidateTimes;
VoltageOutput = PulsePalVolts2Bits(Voltages, PulsePalSystem.RegisterBits);


if ~((TrainID == 1) || (TrainID == 2))
    error('The first argument must be the stimulus train ID (1 or 2)')
end

if TrainID == 1
    OpCode = 75;
else
    OpCode = 76;
end


if strcmp(PulsePalSystem.OS, 'Microsoft Windows XP') && PulsePalSystem.FirmwareVersion < 20
    % This section calculates whether the transmission will result in
    % attempting to send a string of a multiple of 64 bytes, which will cause
    % WINXP machines to crash. If so, a byte is added to the transmission and
    % removed at the other end.
    if nPulses < 200
        USBPacketLengthCorrectionByte = uint8((rem(nPulses, 16) == 0));
    else
        nFullPackets = ceil(length(TimeOutput)/200) - 1;
        RemainderMessageLength = nPulses - (nFullPackets*200);
        if  uint8((rem(RemainderMessageLength, 16) == 0)) || (uint8((rem(nPulses, 16) == 0)))
            USBPacketLengthCorrectionByte = 1;
        else
            USBPacketLengthCorrectionByte = 0;
        end
    end
    if USBPacketLengthCorrectionByte == 1
        nPulsesByte = uint32(nPulses+1);
    else
        nPulsesByte = uint32(nPulses);
    end
    ArCOM_PulsePal('write', PulsePalSystem.SerialPort, [PulsePalSystem.OpMenuByte OpCode USBPacketLengthCorrectionByte], 'uint8',...
        nPulsesByte, 'uint32');
    % Send PulseTimes
    nPackets = ceil(length(TimeOutput)/200);
    Ind = 1;
    if nPackets > 1
        for x = 1:nPackets-1
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, TimeOutput(Ind:Ind+199), 'uint32');
            Ind = Ind + 200;
        end
        if USBPacketLengthCorrectionByte == 1
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, [TimeOutput(Ind:length(TimeOutput)) 5], 'uint32');
        else
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, TimeOutput(Ind:length(TimeOutput)), 'uint32');
        end
    else
        if USBPacketLengthCorrectionByte == 1
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, [TimeOutput 5], 'uint32');
        else
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, TimeOutput, 'uint32');
        end
    end
    
    % Send voltages
    if nPulses > 800
        ArCOM_PulsePal('write', PulsePalSystem.SerialPort, VoltageOutput(1:800), 'uint8');
        if USBPacketLengthCorrectionByte == 1
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, [VoltageOutput(801:nPulses) 5], 'uint8');
        else
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, VoltageOutput(801:nPulses), 'uint8');
        end
    else
        if USBPacketLengthCorrectionByte == 1
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, [VoltageOutput(1:nPulses) 5], 'uint8');
        else
            ArCOM_PulsePal('write', PulsePalSystem.SerialPort, VoltageOutput(1:nPulses), 'uint8');
        end
    end
    
else % This is the normal transmission scheme, as a single bytestring
    if PulsePalSystem.FirmwareVersion < 20
        ArCOM_PulsePal('write', PulsePalSystem.SerialPort, [PulsePalSystem.OpMenuByte OpCode 0], 'uint8',...
            [nPulses TimeOutput], 'uint32', VoltageOutput, 'uint8');
    else % Pulse Pal 2
        ArCOM_PulsePal('write', PulsePalSystem.SerialPort, [PulsePalSystem.OpMenuByte OpCode], 'uint8',...
            [nPulses TimeOutput], 'uint32', VoltageOutput, 'uint16');
    end
end
ConfirmBit = ArCOM_PulsePal('read', PulsePalSystem.SerialPort, 1, 'uint8'); % Get confirmation