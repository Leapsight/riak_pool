

# Module riak_pool #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `riak_pool` behaviour.__<br /> Required callback functions: `start/0`, `stop/0`, `add_pool/2`, `remove_pool/1`, `checkout/2`, `checkin/3`.

<a name="types"></a>

## Data Types ##


<a name="config()"></a>


### config() ###


<pre><code>
config() = #{min_size =&gt; pos_integer(), max_size =&gt; pos_integer(), idle_removal_interval_secs =&gt; non_neg_integer(), max_idle_secs =&gt; non_neg_integer()}
</code></pre>


<a name="opts()"></a>


### opts() ###


<pre><code>
opts() = #{deadline =&gt; pos_integer(), timeout =&gt; pos_integer(), max_retries =&gt; non_neg_integer(), retry_backoff_interval_min =&gt; non_neg_integer(), retry_backoff_interval_max =&gt; non_neg_integer(), retry_backoff_type =&gt; jitter | normal}
</code></pre>


<a name="functions"></a>

## Function Details ##

<a name="add_pool-2"></a>

### add_pool/2 ###

<pre><code>
add_pool(Poolname::atom(), Config::<a href="#type-config">config()</a>) -&gt; ok | {error, any()}
</code></pre>
<br />

<a name="checkin-2"></a>

### checkin/2 ###

<pre><code>
checkin(Poolname::atom(), Pid::pid()) -&gt; ok
</code></pre>
<br />

<a name="checkin-3"></a>

### checkin/3 ###

<pre><code>
checkin(Poolname::atom(), Pid::pid(), Status::atom()) -&gt; ok
</code></pre>
<br />

<a name="checkout-1"></a>

### checkout/1 ###

<pre><code>
checkout(Poolname::atom()) -&gt; {ok, pid()} | {error, any()}
</code></pre>
<br />

<a name="checkout-2"></a>

### checkout/2 ###

<pre><code>
checkout(Poolname::atom(), Opts::<a href="#type-opts">opts()</a>) -&gt; {ok, pid()} | {error, any()}
</code></pre>
<br />

<a name="execute-3"></a>

### execute/3 ###

<pre><code>
execute(Poolname::atom(), Fun::fun((RiakConn::pid()) -&gt; Result::any()), Opts::map()) -&gt; {true, Result::any()} | {false, Reason::any()} | no_return()
</code></pre>
<br />

Executes a number of operations using the same Riak client connection
from pool `Poolname`.
The connection will be passed to the function object `Fun` and also
temporarily stored in the process dictionary for the duration of the call
and it is accessible via the [`get_connection/0`](#get_connection-0) function.

The function returns:
* `{true, Result}` when a connection was succesfully checked out from the
pool `Poolname`. `Result` is is the value of the last expression in
`Fun`.
* `{false, Reason}` when the a connection could not be obtained from the
pool `Poolname`. `Reason` is `busy` when the pool runout of connections or `{error, Reason}` when it was a Riak connection error such as
`{error, timeout}/ or `{error, overload}`.

<a name="get_connection-0"></a>

### get_connection/0 ###

<pre><code>
get_connection() -&gt; undefined | pid()
</code></pre>
<br />

Returns a Riak connection from the process
dictonary or `undefined` if there is none.

<a name="has_connection-0"></a>

### has_connection/0 ###

<pre><code>
has_connection() -&gt; boolean()
</code></pre>
<br />

Returns `true` if there is a Riak connection stored in the process
dictionary or `false` otherwise.

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

Starts a pool

<a name="stop-0"></a>

### stop/0 ###

<pre><code>
stop() -&gt; ok
</code></pre>
<br />

