use driver_domains;

var A: [Dom4D] 4*int = {(...Dom4D.dims())};
var B: [Dom4D] 4*int;

resetCommDiagnostics();
startCommDiagnostics();
B = A;
stopCommDiagnostics();
writeln(getCommDiagnostics());
for i in Dom4D do if B[i]!=i then writeln("ERROR: B[", i, "]==", B[i]);
