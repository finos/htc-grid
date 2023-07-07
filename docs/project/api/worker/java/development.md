# Developing Java Worker Function

HTC-Grid comes with examples demonstrating how to build Python3, Java, and C++ based Worker functions. The overall concept for Java is very similar to Python3, thus refer to architecture diagrams from Python3 examples.


## Java Deploying Simple Mock Compute Engine

The most simplest mock computation example can be found in:   ``/examples/workloads/java/mock_computation``. The java class simply receives payload, prints its, sleeps for a configured duration and then returns.

The example contains the following file structure:

- **src/**         # The folder containing MockComputeEngine.java
- **pom.xml**      # configuration file to compile and package project using Maven
- **Makefile**     # This is the make file that is being called during HTC-Grid happy-path build process to compile and package mock function into a Lambda package.
- **Dockerfile**   # This is a sample docker file that can be used to for testing of lambda function locally with Docker. Unlike Python and C++ examples that compile all dependencies in a docker file, Java examples are compiled locally on the machine that performs the deployment.

This mock compute backend can be used with ``client.py``

### Deploy HTC-Grid with Java Mock Compute Lambda functions

To deploy HTC-Grid in this configuration use the default **happy-path** deployment steps from the documentation, except use the following functions to build and deploy

```bash
make java-happy-path TAG=$TAG REGION=$HTCGRID_REGION
make auto-apply-java-runtime  TAG=$TAG REGION=$HTCGRID_REGION GRAFANA_ADMIN_PASSWORD=
```

## Java Deploying Quant Lib

This example is located in ``/examples/workloads/java/quant_lib`` and shows how to build a java worker lambda with dependency. Specifically in this case we use a C++ QuantLib which is accessed via JNI, i.e., first a lambda function written in java is invoked which then calls C++ library. There are several additional steps involved in this process.


### 1. Build QuantLib and SWIG

The [QuantLib](https://www.quantlib.org/) is an open source project that is aimed at providing a comprehensive software framework for quantitative finance. [QuantLib-SWIG](https://github.com/lballabio/QuantLib-SWIG/tree/master)  provides the means to use QuantLib from a number of languages including Java.

First follow official steps to download QuantLib release or [build it yourself](https://www.quantlib.org/install/linux.shtml) which is straighforward.

Then build QuantLib-SWIG, note when running ./configure exclude all other languages except for Java. Follow the official steps to build the library.

At the end of the process you should get the following libraries and a JAR:

```bash
libQuantLib.so.0
libQuantLibJNI.so
QuantLib.jar
```
These libraries are not part of the HTC-Grid project and **not provided** in a form of artifacts or built automatically.


### 2. Confgiure Java Lambda Function for compilation

Edit static dependency for quantlib in ''pom.xml'', make sure that **QuantLib.jar** can be located by Maven, default location is ''ql/'' subfolder. This will allow project to be build and pacakged by Maven.

```xml
    <dependency>
      <groupId>org</groupId>
      <artifactId>quantlib</artifactId>
      <version>1.30</version>
      <scope>system</scope>
      <systemPath>${project.basedir}/ql/QuantLib.jar</systemPath>
    </dependency>
```

### 3. Edit Makefile to package Lambda function

The following code in the Makefile is responsible for packaging the Lambda function into a zip file that will be deployed on the worker pods at runtime. Make sure that all 3 required libraries ``libQuantLib.so.0 libQuantLibJNI.so QuantLib.jar``can be copied into ``./lambda/lib/`` otherwise the lambda function will fail with a runtime error.

```Makefile
upload: compile

	rm ./lambda -rf
	rm ./lambda.zip -f

	mkdir lambda

	cp -r ./target/classes/com ./lambda
	cp -r ./target/dependency/ ./lambda/lib

	cp -r ./ql/QuantLib.jar ./lambda/lib/
	cp -r ./ql/libQuantLibJNI.so ./lambda/lib/
	cp -r ./ql/libQuantLib.so.0 ./lambda/lib/
```

### 4. Deploy HTC-Grid with Java QuantLib Lambda functions

To deploy HTC-Grid in this configuration use the default **happy-path** deployment steps from the documentation, except use the following functions to build and deploy

```bash
make java-ql-happy-path TAG=$TAG REGION=$HTCGRID_REGION
make auto-apply-java-runtime  TAG=$TAG REGION=$HTCGRID_REGION GRAFANA_ADMIN_PASSWORD=
```

This example will work with any client workload generator as the main class does not take use of the input arguments, instead, it just demonstrate how java worker lambda can be executed with C++ runtime linked libraries.

