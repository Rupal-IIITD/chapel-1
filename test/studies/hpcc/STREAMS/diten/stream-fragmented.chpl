use Time, Types, Random;
use hpccMultilocale;

use HPCCProblemSize;


param numVectors = 3;
type elemType = real(64),
     indexType = int(64);

config const m = computeProblemSize(elemType, numVectors),
             alpha = 3.0;

config const numTrials = 10,
             epsilon = 0.0;

config const useRandomSeed = true,
             seed = if useRandomSeed then SeedGenerator.clockMS else 314159265;

config const printParams = true,
             printArrays = false,
             printStats = true;


def main() {
  printConfiguration();

  const ProblemSpace: domain(1, indexType) = [1..m];

  const allExecTime: [LocaleSpace] [1..numTrials] real;
  const allValidAnswer: [LocaleSpace] bool;
  
  coforall loc in Locales {
    on loc {
      const MyProblemSpace: domain(1, indexType) 
                          = BlockPartition(ProblemSpace, here.id, numLocales);

      var A, B, C: [MyProblemSpace] elemType;

      initVectors(B, C, ProblemSpace);

      for trial in 1..numTrials {
        const startTime = getCurrentTime();
        local A = B + alpha * C;
        allExecTime(here.id)(trial) = getCurrentTime() - startTime;
      }

      allValidAnswer(here.id) = verifyResults(A, B, C);
    }
  }

  const execTime: [t in 1..numTrials] real 
                = max reduce [loc in LocaleSpace] allExecTime(loc)(t);

  const validAnswer = & reduce allValidAnswer;

  printResults(validAnswer, execTime);
}


def printConfiguration() {
  if (printParams) {
    printProblemSize(elemType, numVectors, m);
    writeln("Number of trials = ", numTrials, "\n");
  }
}


def initVectors(B, C, ProblemSpace) {
  var randlist = new RandomStream(seed);

  randlist.skipToNth(B.domain.low);
  randlist.fillRandom(B);
  randlist.skipToNth(ProblemSpace.numIndices + C.domain.low);
  randlist.fillRandom(C);

  if (printArrays) {
    writelnFragArray("B is: ", B, "\n");
    writelnFragArray("C is: ", C, "\n");
  }
}


def verifyResults(A, B, C) {
  if (printArrays) then writelnFragArray("A is: ", A, "\n");

  const infNorm = max reduce [i in A.domain] abs(A(i) - (B(i) + alpha * C(i)));

  return (infNorm <= epsilon);
}


def printResults(successful, execTimes) {
  writeln("Validation: ", if successful then "SUCCESS" else "FAILURE");
  if (printStats) {
    const totalTime = + reduce execTimes,
          avgTime = totalTime / numTrials,
          minTime = min reduce execTimes;
    writeln("Execution time:");
    writeln("  tot = ", totalTime);
    writeln("  avg = ", avgTime);
    writeln("  min = ", minTime);

    const GBPerSec = numVectors * numBytes(elemType) * (m / minTime) * 1e-9;
    writeln("Performance (GB/s) = ", GBPerSec);
  }
}
