"""
Using a restriction built for a no-turn feature, convert it to an only-turn feature,
by creating a series of restrictions that restrict everything other than the allowed turn.

This is straightforward for via nodes. For via ways it is more complicated. Consider an intersection
like this:

                      |
                      H        /
                      o       St
                      l      /
                      l     m 
                      y    l
                          E
                      St /
                      | /
                      |/
                      |
                      E
                      l
                      m

                      St
                      |
                      |----Oak St-------o (dead end)
---Cypress St---------|
                      |
                      |
                      |

Suppose that there is an only_left_turn restriction from EB Cypress St to NB Holly St via NB Elm St.
In this case, all of the following actions need to be restricted

EB Cypress -> SB Elm
EB Cypress -> NB Elm -> EB Oak
EB Cypress -> NB Elm -> NB Elm
EB Cypress -> NB Elm -> SB Elm via u-turn @ Oak  (tricky)
EB Cypress -> NB Elm -> SB Elm via u-turn @ Holly

So what needs to happen is for each of the edges in the restriction, we need to create a turn restriction starting with the
from way, passing through all the edges up to that point, and then ending with all edges _other_ than the one that allows you to continue.

It is critical that each restriction start at the very beginning of the only restriction and include all edges up to where things went off
the rails. Consider a counterexample. Suppose that we implemented the above restriction as:
No right from NB Cypress to SB Elm
No right from NB Elm to EB Oak
No straight from NB Elm to NB Elm at Holly
No U turn NB Elm at Oak

This would restrict the maneuvers above, but would also prevent these legal maneuvers:
NB Elm -> EB Oak
NB Elm -> NB Elm at Holly
qed

Only restrictions with via ways rather than nodes are uncommon, but do exist (e.g. https://www.openstreetmap.org/relation/7644917). This
algorithm is general enough to support arbitrary number of edges (though things could get out of hand if there are many).

It's technically undefined what an only restriction with a via way means. From the OSM wiki:  Going to other ways from the via point is forbidden with this relation.
and via is defined as a node. One reading would be to say that an only-right-turn restriction from ways A - B - C would mean that after
traveling A-B you can only go to C, but A-D would be allowed. But I think what this code actually does is more likely to be what is intended. From Way A at the node where
it intersects way B, you can only go B-C.
"""
function convert_restriction_to_only_turn(G, restric)
    restrictions = Vector{TurnRestriction}()
    for segment_of_restriction_idx in 1:(length(restric.segments) - 1)
        v = restric.segments[segment_of_restriction_idx]
        next_v = restric.segments[segment_of_restriction_idx + 1]
        for nbr in outneighbors(G, v)
            if nbr != next_v
                push!(restrictions, TurnRestriction(
                    [restric.segments[1:segment_of_restriction_idx]; nbr],
                    restric.osm_id
                ))
            end
        end
    end
    return restrictions
end