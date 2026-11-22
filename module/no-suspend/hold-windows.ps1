$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class NoSuspend {
    private const uint Continuous = 0x80000000;
    private const uint SystemRequired = 0x00000001;

    [DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint flags);

    public static void Hold() {
        if (SetThreadExecutionState(Continuous | SystemRequired) == 0) {
            throw new InvalidOperationException("Windows refused the system power request.");
        }

        try {
            Console.WriteLine("ready");
            Console.Out.Flush();
            Console.ReadLine();
        } finally {
            SetThreadExecutionState(Continuous);
        }
    }
}
'@

[NoSuspend]::Hold()
