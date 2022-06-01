


if [ -f /tmp/cancelation_trigger ] # cancelation
do
  rm /tmp/cancelation_trigger
  kill -9 pidoflambda-rie
done