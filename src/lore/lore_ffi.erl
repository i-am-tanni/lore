-module(lore_ffi).

-export([
    iolist_map/2, iolist_map_fold/3
]).

% Recurses through any nested lists and then applies the Fun to any elements
% found within.
%
iolist_map(IoList, Fun) when is_list(IoList) ->
    lists:map(
        fun(X) -> iolist_map(X, Fun) end,
        IoList
    );
iolist_map(Element, Fun) ->
    Fun(Element).

% Recurses through any nested lists and then applies the Fun to any elements
% found within while keeping an accumulator.
%
iolist_map_fold(IoList, Acc0, Fun) when is_list(IoList) ->
    lists:mapfoldl(
        fun(X, Acc1) -> iolist_map_fold(X, Acc1, Fun) end,
        Acc0,
        IoList
    );
iolist_map_fold(Element, Acc, Fun) ->
    Fun(Acc, Element).
