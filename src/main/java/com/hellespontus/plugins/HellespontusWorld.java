package com.hellespontus.plugins;

import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockCanBuildEvent;
import org.bukkit.event.block.BlockEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.util.Vector;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Logger;

public class HellespontusWorld extends JavaPlugin implements Listener{
    Logger log = Logger.getLogger("Minecraft");
    List<Area> unbreakable;
    Map<String, Vector> points;
    Map<String, BlockTuple> blocklines;

    public void onEnable(){
        getServer().getPluginManager().registerEvents(this, this);
        
        List<Integer> worldSpawnPoint = getConfig().getIntegerList("world_spawnpoint");
        getServer().getWorld("world").setSpawnLocation(worldSpawnPoint.get(0), worldSpawnPoint.get(1), worldSpawnPoint.get(2));
        
        unbreakable = new ArrayList<Area>();
        for(Object obj : getConfig().getList("unbreakable")){
            @SuppressWarnings("unchecked")
            List<Integer> point = (List<Integer>) obj;
            Area area = new Area();
            area.point = new Vector(point.get(0), point.get(1), point.get(2));
            if(point.size() > 3)
                area.radius = point.get(3);
            unbreakable.add(area);
        }
        
        int usersCount = 10;
        
        points = new HashMap<String, Vector>(usersCount);
        getCommand("point").setExecutor(new PointCommandExecutor());
        
        blocklines = new HashMap<String, BlockTuple>(usersCount);
        getCommand("blockline").setExecutor(new BlocklineCommandExecutor());
    }

    public void onDisable(){
        
    }
    
    @EventHandler
    public void onBlockBreak(BlockBreakEvent event){
        if(isBlockChangeDisabled(event)){
            event.setCancelled(true);
        }
    }
    
    @EventHandler
    public  void  onBlockBuild(BlockPlaceEvent event){
        if(isBlockChangeDisabled(event)){
            event.setCancelled(true);
        } else {
            Block block = event.getBlockPlaced();
            BlockTuple tuple = blocklines.get(event.getPlayer().getName());
            if(tuple == null){
                tuple = new BlockTuple();
                blocklines.put(event.getPlayer().getName(), tuple);
            }
            tuple.add(block.getLocation().toVector(), block.getTypeId());
        }
    }
    
    private boolean isBlockChangeDisabled(BlockEvent event) {
        Vector location = event.getBlock().getLocation().toVector();
        for(Area area : unbreakable)
            if(area.point.distance(location) < area.radius){
                getServer().broadcastMessage("Block break cancelled. Unbreakable point " +
                        area.point.toString() + ", dist= " + Math.round(area.point.distance(location)) + "/" + area.radius);
                return true;
            }
        return false;
    }

    private class PointCommandExecutor implements CommandExecutor {
        @Override
        public boolean onCommand(CommandSender commandSender, Command command, String s, String[] strings) {
            if(!(commandSender instanceof Player)){
                commandSender.sendMessage("Only online players can invoke this command");
                return true;
            }
            Vector point = ((Player) commandSender).getLocation().toVector();
            Vector lastPoint = points.get(commandSender.getName());
            StringBuilder msg = new StringBuilder("Point: [" + point.getBlockX() + ", " + point.getBlockY() + ", " + point.getBlockZ() + "]");
            if(lastPoint != null){
                msg.append("   Distance: " + Math.round(lastPoint.distance(point)));
            }
            commandSender.sendMessage(msg.toString());
            points.put(commandSender.getName(), point);
            return true;
        }
    }

    private class BlocklineCommandExecutor implements CommandExecutor {
        @Override
        public boolean onCommand(CommandSender commandSender, Command command, String s, String[] args) {
            if(!(commandSender instanceof Player)){
                commandSender.sendMessage("Only online players can invoke this command");
                return true;
            }
            if(!((args.length == 1 || args.length == 2) && Integer.parseInt(args[0]) >= 0)){
                commandSender.sendMessage("Invalig arguments, see command usage");
                return true;
            }
            BlockTuple tuple = blocklines.get(commandSender.getName());
            if(tuple == null || !tuple.consistent()) {
                commandSender.sendMessage("Previous placed blocks not consistent");
                return true;
            }
            int amount = Integer.parseInt(args[0]);
            if(amount > 100) {
                commandSender.sendMessage("Amount too big");
                return true;
            }
            Vector normal = tuple.normal();
            Vector v = tuple.getPos();
            World world = ((Player) commandSender).getLocation().getWorld();
            Material blockType = Material.getMaterial(tuple.getType());
            if(args.length > 1 && args[1].equals("air"))
                blockType = Material.AIR;
            boolean blockTypeIsEmpty = blockType == Material.AIR;
            int counter;
            for(counter = 0; counter < amount; counter++) {
                v.add(normal);
                Block block = world.getBlockAt(v.toLocation(world));
                if(blockTypeIsEmpty || block.isEmpty() || block.isLiquid())
                    block.setType(blockType);
                else
                    break;
            }
            tuple.clear();
            commandSender.sendMessage("Blocks created: " + counter);
            return true;
        }
    }
    
    private static class Area{
        public Vector point;
        public int radius = 10;
    }
    
    private static class BlockTuple{
        private Vector firstPos;
        private int firstType;

        private Vector lastPos;
        private int lastType;
        
        public void add(Vector pos, int type) {
            firstType = lastType;
            firstPos = lastPos;
            lastType = type;
            lastPos = pos;
        }
        
        public boolean consistent() {
            return  firstPos != null && lastPos != null && firstType == lastType && firstPos.distance(lastPos) == 1;
        }
        
        public Vector normal() {
            return lastPos.clone().subtract(firstPos);
        }
        
        public Vector getPos() {
            return lastPos.clone();
        }
        
        public int getType() {
            return lastType;
        }
        
        public void clear(){
            firstPos = null;
            lastPos = null;
            firstType = 0;
            lastType = 0;
        }
    }    
}
