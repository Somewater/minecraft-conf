#!/bin/bash
cd CraftBukkit
mvn clean package
cd ..
cp CraftBukkit/target/craftbukkit-1.5.2-R1.0.jar craftbukkit.jar
