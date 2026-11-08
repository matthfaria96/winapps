// astest.exe PORTA — DIAGNÓSTICO: conecta no Analysis Services local (msmdsrv do Power BI)
// usando o ADOMD do Power BI e imprime a exceção completa.
using System;
using System.Reflection;
class P {
    static int Main(string[] a) {
        var bin = @"C:\Program Files\Microsoft Power BI Desktop\bin\";
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) => {
            var f = bin + new AssemblyName(e.Name).Name + ".dll";
            return System.IO.File.Exists(f) ? Assembly.LoadFrom(f) : null;
        };
        var asm = Assembly.LoadFrom(bin + "Microsoft.PowerBI.AdomdClient.dll");
        var t = asm.GetType("Microsoft.AnalysisServices.AdomdClient.AdomdConnection");
        dynamic c = Activator.CreateInstance(t, "Data Source=localhost:" + a[0]);
        try { c.Open(); Console.WriteLine("CONECTOU: " + c.ServerVersion); c.Close(); return 0; }
        catch (Exception e) { Console.WriteLine(e.ToString()); return 1; }
    }
}
