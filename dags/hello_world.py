from datetime import datetime
from airflow import DAG
from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.python_operator import PythonOperator


def print_hello():
 return 'Hello, world!'


dag = DAG('hello_world', 
    description='Hello world example', 
    schedule_interval='0 12 * * *', 
    start_date=datetime(2021, 1, 1), 
    catchup=False)

start = DummyOperator(task_id='start', dag=dag)

hello = PythonOperator(task_id='hello_task', python_callable=print_hello, dag=dag)

finish = DummyOperator(task_id='finish', dag=dag)

start >> hello >> finish
