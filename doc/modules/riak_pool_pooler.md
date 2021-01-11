

# Module riak_pool_pooler #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`riak_pool`](riak_pool.md).

<a name="functions"></a>

## Function Details ##

<a name="add_pool-2"></a>

### add_pool/2 ###

<pre><code>
add_pool(Poolname::atom(), Config::<a href="riak_pool.md#type-config">riak_pool:config()</a>) -&gt; ok | {error, any()}
</code></pre>
<br />

<a name="checkin-3"></a>

### checkin/3 ###

<pre><code>
checkin(Poolname::atom(), Pid::pid(), Status::atom()) -&gt; ok
</code></pre>
<br />

<a name="checkout-2"></a>

### checkout/2 ###

<pre><code>
checkout(Poolname::atom(), Opts::<a href="riak_pool.md#type-opts">riak_pool:opts()</a>) -&gt; {ok, pid()} | {error, any()}
</code></pre>
<br />

<a name="remove_pool-1"></a>

### remove_pool/1 ###

<pre><code>
remove_pool(Poolname::atom()) -&gt; ok | {error, any()}
</code></pre>
<br />

<a name="start-0"></a>

### start/0 ###

<pre><code>
start() -&gt; ok
</code></pre>
<br />

<a name="stop-0"></a>

### stop/0 ###

<pre><code>
stop() -&gt; ok
</code></pre>
<br />

