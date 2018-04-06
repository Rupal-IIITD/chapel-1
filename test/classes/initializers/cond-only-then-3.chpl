// Confirm that the compiler allows a conditional with different
// use of field initializers

record MyRec {
  var x : int = 10;
  var y : int = 20;

  proc init(a : int) {
    if a < 10 then
      x = 20;
    else
      writeln('Else does not explicitly initialize x');

    this.complete();
  }
}

proc main() {
  var r1 : MyRec = new MyRec( 5);
  var r2 : MyRec = new MyRec(15);

  writeln('r1: ', r1);
  writeln('r2: ', r2);
}
